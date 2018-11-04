require 'rubygems'
require 'stemmify'
require 'fileutils'
require 'shellwords'
require 'json'
require 'benchmark'
require 'pp'
require 'pry'
require 'progressbar'


results = Hash.new do |h,k|
  h[k] = []
end
files = Dir.glob("results/**/*.json")

progress = ProgressBar.create(title: "Files", total: files.length)

rt = Benchmark.realtime do
  files.each do |file|
    file_data = nil
    File.open(file, 'rb') do |f|
      file_data = f.read
    end
    file_data = JSON.parse(file_data)

    id = file_data["id"]
    file_data["paragraphs"].each_with_index do |paragraph, i|
      paragraph["words"].each do |word, count|
        $stderr.puts "count > 99!" if count > 99
        results[word].push sprintf("%02d:%s:%d", count, id, i)
      end
    end

    progress.increment
  end
end
progress.finish
puts "Completed in #{rt}s"
results.each_value(&:sort!)

json = JSON.pretty_generate(results)
File.open("db.json", "wb") do |f|
  f.write(json)
end
