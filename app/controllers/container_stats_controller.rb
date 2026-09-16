require "docker_engine_ruby"

#
# Provides live container resource-usage metrics (CPU, memory, network, block I/O)
# for the vega area charts. Separate from ContainersController because polling
# the Docker stats API maintains its own accumulated time-series in the cache and
# serves both an HTML partial (initial chart specs) and a JSON endpoint (streaming).
#
class ContainerStatsController < BaseAdminController
  include DockerClientConcern

  # How long to retain samples in the in-memory time series cache.
  POINTS_WINDOW = 10.minutes

  def stats
    fetch_stats
    @payload = stats_payload
    append_point(@payload)

    respond_to do |format|
      format.html do
        render partial: "containers/show/stats", locals: { points: points, point: @payload }
      end
      format.json do
        render json: { sample: @payload, points: points }
      end
    end
  rescue DockerEngineRuby::Errors::Error
    render json: { sample: {}, points: points }
  end

  private

  def fetch_stats
    cache_key = "container_stats_prev:#{params[:id]}"
    @prev_stats, @prev_polled_at = Rails.cache.read(cache_key)

    @stats = docker_client.containers.stats(params[:id], stream: false)
    @polled_at = Time.current
    @cpu_stats = @stats.cpu_stats
    @memory_stats = @stats.memory_stats

    Rails.cache.write(cache_key, [ @stats, @polled_at ])
  rescue DockerEngineRuby::Errors::APIStatusError
    # stats not available (container not running, etc.)
  end

  #
  # A single normalized, JSON-friendly sample.
  #
  def stats_payload
    {
      time: (@polled_at || Time.current).to_f * 1000, # ms epoch for temporal vega scale
      cpu_pct: cpu_percent,
      mem_used: @memory_stats&.usage,
      mem_limit: @memory_stats&.limit,
      mem_pct: memory_percent,
      net_rx: network_rate(:rx_bytes),
      net_tx: network_rate(:tx_bytes),
      blk_read: block_io_rate(:read),
      blk_write: block_io_rate(:write)
    }
  end

  def points_key
    "container_stats_points:#{params[:id]}"
  end

  def points
    @points ||= begin
      fresh = prune((Rails.cache.read(points_key) || []))
      Rails.cache.write(points_key, fresh)
      fresh
    end
  end

  def append_point(point)
    next_points = prune(points + [ point ])
    Rails.cache.write(points_key, next_points)
    @points = next_points
  end

  #
  # Trim samples that fall outside the retention window (older than
  # POINTS_WINDOW). Points are stored chronologically, so we can drop the
  # leading prefix once a point is old enough.
  #
  def prune(series)
    cutoff = (Time.current - POINTS_WINDOW).to_f * 1000 # ms epoch
    series.drop_while { |p| p[:time].to_f < cutoff }
  end

  #
  # CPU utilization is computed as a delta between the current sample and the
  # previous sample from the Docker API, normalized over the reported online
  # CPU count. This avoids the plateaus you get from the raw cumulative counters.
  #
  def cpu_percent
    return nil unless @stats
    cpu = @stats.cpu_stats
    pre = @stats.precpu_stats
    return nil unless cpu && pre

    cpu_delta = cpu.cpu_usage&.total_usage.to_f - pre.cpu_usage&.total_usage.to_f
    system_delta = cpu.system_cpu_usage.to_f - pre.system_cpu_usage.to_f
    online = cpu.online_cpus || 1
    return nil if cpu_delta <= 0 || system_delta <= 0

    (((cpu_delta / system_delta) * online * 100).clamp(0, 100)).round(1)
  end

  def memory_percent
    return nil unless @memory_stats&.usage && @memory_stats.limit && @memory_stats.limit > 0
    ((@memory_stats.usage.to_f / @memory_stats.limit) * 100).round(1)
  end

  #
  # Network throughput (bytes/sec) computed as a delta between consecutive
  # polls, aggregated across all networks. Returns nil when there isn't a
  # previous sample to diff against.
  #
  def network_rate(key)
    return nil unless @prev_stats && @polled_at && @prev_polled_at

    elapsed = @polled_at - @prev_polled_at
    return nil if elapsed <= 0

    current = network_total(@stats, key)
    previous = network_total(@prev_stats, key)
    return nil unless current && previous

    delta = current - previous
    return nil if delta < 0
    (delta / elapsed).round
  end

  def network_total(stats, key)
    networks = stats&.networks
    return nil unless networks.respond_to?(:values) && networks.values.any?
    networks.values.sum { |n| n.public_send(key).to_f }
  rescue NoMethodError
    nil
  end

  #
  # Block I/O bytes/sec computed as a delta between consecutive polls.
  #
  def block_io_rate(kind)
    return nil unless @prev_stats && @polled_at && @prev_polled_at

    elapsed = @polled_at - @prev_polled_at
    return nil if elapsed <= 0

    current = block_io_total(@stats, kind)
    previous = block_io_total(@prev_stats, kind)
    return nil unless current && previous

    delta = current - previous
    return nil if delta < 0
    (delta / elapsed).round
  end

  def block_io_total(stats, kind)
    services = stats&.blkio_stats&.io_service_bytes_recursive
    return nil unless services
    services.select { |s| s.op.to_s == kind.to_s }.sum { |s| s.value.to_f }
  rescue NoMethodError
    nil
  end
end
