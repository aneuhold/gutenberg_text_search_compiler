require 'rubygems'
require 'stemmify'
require 'fileutils'
require 'shellwords'
require 'json'
require 'benchmark'
require 'pp'
require 'pry'
require 'progressbar'
require 'optionparser'

class Aggregator
  attr_accessor :directories

  def initialize
    self.directories = ["results"]
  end

  def aggregate!
    results = Hash.new do |h,k|
      h[k] = []
    end
    files = directories.map do |dir|
      Dir.glob(File.join(dir, "**/*.json"))
    end.flatten.uniq

    progress = ProgressBar.create(title: "Files", total: files.length, format: "%t (%c/%C): %w")

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


    dir = "results_aggregate"
    FileUtils.mkdir_p dir
    puts "Completed in #{rt}s"
    puts "Writing File"
    results.each_value(&:sort!)
    rt = Benchmark.realtime do
      json = JSON.generate(results)
      File.open(File.join(dir, "db.json"), "wb") do |f|
        f.write(json)
      end
    end


    puts "Writing Word list"
    rt = Benchmark.realtime do
      File.open(File.join(dir, "words.txt"), "wb") do |f|
        f.write(results.keys.join("\n"))
      end
    end
    puts "Completed in #{rt}s"


    puts "Writing Letter Lists"
    rt = Benchmark.realtime do
      first_letter = results.group_by { |key, value| key[0] }
      first_letter.each do |letter, results|
        json = JSON.generate(results.to_h)
        File.open(File.join(dir, "#{letter}.json"), "wb") do |f|
          f.write(json)
        end
      end
    end
    puts "Completed in #{rt}s"
  end
end


aggregator = Aggregator.new



OptionParser.new do |opts|
  opts.banner = "Usage: parse.rb [options]"

  opts.on("-d=dir", "--directory=dir,dir,dir", Array, "directory to parse") do |v|
    aggregator.directories = v
  end

  opts.on("-p", "show progress") do
    aggregator.progressbar = ProgressBar.create title: "Directories", format: "%t (%c/%C): %w"
  end

end.parse!


aggregator.parse!
