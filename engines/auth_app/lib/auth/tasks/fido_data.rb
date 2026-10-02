require "open-uri"

ROOT_DIR = File.expand_path("../../../tmp", __dir__)
OUTPUT_FILE = File.expand_path("../aaguid.rb", __dir__)
REMOTE_FILES = [
  {
    label: "passkey-authenticator-aaguids",
    source: "https://github.com/passkeydeveloper/passkey-authenticator-aaguids/raw/refs/heads/main/combined_aaguid.json",
    dest: "combined_aaguid.json"
  }
  # {
  #   label: "mds3",
  #   source: "https://mds3.fidoalliance.org/",
  #   dest: "mds3.jwt"
  # }
]

class Cache < Hash
  def read(name, _options = nil)
    self[name]
  end

  def write(name, value, _options = nil)
    self[name] = value
  end
end

desc "Download fido2 identification sources"
task "download" do
  FileUtils.mkdir_p(ROOT_DIR)
  REMOTE_FILES.each do |file|
    dest = File.join(ROOT_DIR, file[:dest])
    source = file[:source]
    label = file[:label]
    puts "DOWNLOADING #{label}"
    puts "  REMOTE: #{source}"
    puts "  LOCAL: #{dest}"
    if File.exist?(dest)
      puts "  SKIPPING: file exists"
    else
      File.open(dest, "w") do |output|
        URI.open(source) do |input|
          output.write(input.read)
        end
      end
    end
  end
end

desc "Generate fido2 identification map"
task "generate" do
  require "fido_metadata"
  entries = {}

  FidoMetadata.configure do |config|
    config.cache_backend = Cache.new
  end
  store = FidoMetadata::Store.new
  toc = store.table_of_contents
  toc.entries.map do |e|
    if e.aaguid && e.aaguid != ""
      entries[e.aaguid] = e.metadata_statement.description
    end
  end

  aaguid_json_filename = File.join(ROOT_DIR, "combined_aaguid.json")
  JSON.parse(File.read(aaguid_json_filename)).map do |k, v|
    if k && k != ""
      entries[k] = v["name"]
    end
  end

  File.open(OUTPUT_FILE, "w") do |file|
    file.write("module Auth\n")
    file.write("  AAGUID = {\n")
    entries.each do |aaguid, description|
      file.write(%[    "#{aaguid}" => "#{description}",\n])
    end
    file.write(%[    "" => ""\n])
    file.write("  }.freeze\n")
    file.write("end")
  end
  puts "WROTE #{OUTPUT_FILE}"
end
