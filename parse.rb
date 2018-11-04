require 'rubygems'
require 'stemmify'
require 'fileutils'
require 'shellwords'
require 'json'
require 'benchmark'
require 'pp'
require 'pry'

STOP_WORDS = [ # ripped off from https://github.com/brez/stopwords/blob/master/lib/stopwords.rb
  'a','cannot','into','our','thus','about','co','is','ours','to','above',
  'could','it','ourselves','together','across','down','its','out','too',
  'after','during','itself','over','toward','afterwards','each','last','own',
  'towards','again','eg','latter','per','under','against','either','latterly',
  'perhaps','until','all','else','least','rather','up','almost','elsewhere',
  'less','same','upon','alone','enough','ltd','seem','us','along','etc',
  'many','seemed','very','already','even','may','seeming','via','also','ever',
  'me','seems','was','although','every','meanwhile','several','we','always',
  'everyone','might','she','well','among','everything','more','should','were',
  'amongst','everywhere','moreover','since','what','an','except','most','so',
  'whatever','and','few','mostly','some','when','another','first','much',
  'somehow','whence','any','for','must','someone','whenever','anyhow',
  'former','my','something','where','anyone','formerly','myself','sometime',
  'whereafter','anything','from','namely','sometimes','whereas','anywhere',
  'further','neither','somewhere','whereby','are','had','never','still',
  'wherein','around','has','nevertheless','such','whereupon','as','have',
  'next','than','wherever','at','he','no','that','whether','be','hence',
  'nobody','the','whither','became','her','none','their','which','because',
  'here','noone','them','while','become','hereafter','nor','themselves','who',
  'becomes','hereby','not','then','whoever','becoming','herein','nothing',
  'thence','whole','been','hereupon','now','there','whom','before','hers',
  'nowhere','thereafter','whose','beforehand','herself','of','thereby','why',
  'behind','him','off','therefore','will','being','himself','often','therein',
  'with','below','his','on','thereupon','within','beside','how','once',
  'these','without','besides','however','one','they','would','between','i',
  'only','this','yet','beyond','ie','onto','those','you','both','if','or',
  'though','your','but','in','other','through','yours','by','inc','others',
  'throughout','yourself','can','indeed','otherwise','thru','yourselves'
].map(&:stem)

BLANK_LINE_REGEXP = /[\n\r]{2,}/
START_REGEXP = /^\*+\s*START[^$]*PROJECT GUTENBERG[^\*]*\*{3,}\s*$/im
INITIAL_CHOMP_REGEXP = /\*{3,}[^*]*\*{3,}\s*/
END_REGEXP = /^\*+\s*END[^$]*PROJECT GUTENBERG/im
PUNCTUATION_REGEXP = /\p{Punct}+$/
MINIMUM_WORDS = 10

def whitelisted_word? word
  @whitelist ||= begin
                   if File.exist? "whitelist.txt"
                     File.read("whitelist.txt").split
                   else
                     generate_whitelist
                   end
                 end

end

def generate_whitelist
  @whitelist = (File.readlines("/usr/share/dict/words").map { |word| word.chomp.downcase.stem } - STOP_WORDS).uniq
  File.open("whitelist.txt", "wb") do |f|
    f.write @whitelist.join("\n")
  end
end

def unzip f
  %x{unzip #{Shellwords.shellescape(f)}}
end

def cleanup
  Dir.glob("*.txt").each do |f|
    FileUtils.rm f
  end

  Dir.glob("*").each do |f|
    FileUtils.rm_r f if File.directory? f
  end
end

def paragraphs text
  aggregator_hash = Hash.new { |h, k| h[k] = 0 }

  text.split(BLANK_LINE_REGEXP).map do |paragraph|
    words = paragraph.split.each_with_object(aggregator_hash.dup) do |word, memo|
      sanitary_word = word.gsub(PUNCTUATION_REGEXP, '').downcase
      memo[sanitary_word.stem] += 1 if whitelisted_word?(sanitary_word)
    end
    if words.length > MINIMUM_WORDS
      { text: paragraph, words: words }
    end
  end.compact
end

def write_result dir, results_dir, result
  destination_dir = File.join(results_dir, dir)
  FileUtils.mkdir_p destination_dir
  id = File.split(dir).last
  json = JSON.generate({ id: id, paragraphs: result })
  File.open(File.join(destination_dir, "#{id}.json"), "wb") do |f|
    f.write(json)
  end
end

def get_textfile dir
  file = Dir.glob("*.zip").sort.first
  return nil if !file
  unzip file
  Dir.glob("**/*.txt").first
end

def process_directory dir
  puts "Processing: #{dir}"
  rt = Benchmark.realtime do
    results_dir = File.expand_path('./results')
    Dir.chdir dir do
      textfile = get_textfile dir

      if !textfile
        $stderr.puts "Error getting textfile for #{dir}"
        return false
      end

      file_data = nil

      File.open(textfile, 'rb') do |f|
        file_data = f.read
      end

      start_index = file_data.index START_REGEXP
      end_index = file_data.index END_REGEXP

      if start_index.nil? || end_index.nil?
        $stderr.puts "#{File.join(dir, textfile)} did not match expected regular expressions (s:#{start_index} e:#{end_index})"
        return false
      end

      file_data = file_data[start_index..end_index].gsub(INITIAL_CHOMP_REGEXP, '').encode('UTF-8', invalid: :replace, undef: :replace, replace: '?')
      if file_data.length > 0
        write_result dir, results_dir, paragraphs(file_data)
      else
        $stderr.puts "#{File.join(dir, textfile)} contains no data"
      end
    ensure
      cleanup
    end
  end
  puts "Complete: #{dir} #{rt}s"
end

rt = Benchmark.realtime do
  whitelisted_word? "foo"
  all_files = Dir.glob("gutenberg_sample/**/*.zip")
  files_by_dir = all_files.group_by { |f| f.gsub(/(.*)\/[^\/]*/, "\\1") }
  puts "#{files_by_dir.keys.length} directories detected"
  files_by_dir.each_key.sort.each do |dir|
    process_directory dir
  end
end

puts "Complete in #{rt}s"
