#!/usr/bin/env ruby -w

require 'optparse'
require 'set'

VERSION = [1,0,0]
KINDS = [:"in-use", :"not-in-use", :all]

options = {
  kind: :"not-in-use",
  threshold: 1.0,
  null: false,
  format: "%{sha}\t%{kind}\t%{size}\t%{path}",
  refs: ['HEAD'],
}

OptionParser.new do |opts|
  opts.banner  = "\nSynopsis: Searches the entire history of a git repository for large files "
  opts.banner +=   "and determines their current in-use status."
  opts.banner += "\n"
  opts.banner += "\nUsage: big-file-finder.rb [options]"
  opts.separator "\nOptions:"

  opts.on("-t", "--threshold=THRESHOLD", Float, "File size threshold in MB.",
            "\tDefault: #{options[:threshold]} MB."
  ) do |o|
    options[:threshold] = o
  end
  opts.on("-r", "--refs=REFS", "A comma-separated list of refs to consider when determining in-use/not-in-use status.",
            "\tPassing the special string '-all' like: '--refs=-all' will use all refs in git/refs.",
            "\tDefault: #{options[:refs].join(',')}."
  ) do |o|
    options[:refs] = o.split(',')
  end
  opts.on("-k", "--kind=#{KINDS.join('|')}", KINDS, "Which kind of files to show.",
            "\tAn 'in-use' file is one that is currently being referenced by the head of one of the refs from the 'refs' option.",
            "\tDefault: 'not-in-use'."
  ) do |o|
    options[:kind] = o
  end
  opts.on("-f", "--format=FORMAT", "Output format string, with ruby style string interpolation.",
            "\tAvailable placeholders: sha, path, size, refs, kind.",
            "\tUse bash escaping to pass special characters, e.g.: --format=$'%{path}\\t%{size}",
            "\tDefault: $'#{options[:format].inspect.gsub(/^"|"$/, '')}'"
  ) do |o|
    options[:format] = o
  end
  opts.on(nil, "--[no-]output-refs", "Add a column that lists the refs that currently reference each path.",
            "\tNote: This can be a large list depending on your repository."
  ) do |o|
    options[:output_refs] = o
  end
  opts.on("-z", "--[no-]null", '\0 line termination on output.') do |o|
    options[:null] = o
  end

  opts.on_tail("-h", "--help", "Show this message") do
    puts opts
    exit
  end
  opts.on_tail("--version", "Show version") do
    puts VERSION.join('.')
    exit
  end
end.parse!

if ARGV.any?
  raise "unrecognized arguments: #{ARGV.inspect}"
end

if options[:output_refs]
  options[:format] << "\t%{refs}"
end

# get all defined refs
all_refs = `git for-each-ref --format='%(refname)'`.split("\n")
raise "error finding all refs" if !$?.success?

refs_description = options[:refs].to_a == ['-all'] ? 'Any ref in git/refs' : options[:refs].join(',')

puts %(Finding #{options[:kind]} files larger than #{options[:threshold]} MB.  Refs used to determine "in-use" status: #{refs_description})

if options[:refs] == ['-all']
  options[:refs] = all_refs
end

options[:refs] = options[:refs].to_set

# verify all refs are valid
options[:refs].each do |ref|
  `git show-ref --quiet #{ref}`
  raise "#{ref.inspect} does not appear to be a valid ref for the current repository" if !$?.success?
end

# check the validity of the format string early since the script is a bit slow
_ = options[:format] % {sha: 1, path: 1, size: 1, kind: 1, refs: 1}

options[:terminator] = options[:null] ? "\0" : "\n"

MEGABYTE = 1024**2

options[:threshold] = options[:threshold] * MEGABYTE

all_paths = {} # all paths currently referenced by any ref
current_paths = {} # all paths currently referenced by any ref from the "refs" option

# find all revisions of all current refs so that we can examine the files of every revision
all_revisions = `git rev-list --all`.split("\n").to_set
raise "error running git rev-list" if !$?.success?

# make a lookup of all paths that are currently in use by any ref, and the refs that use them
all_refs.each do |ref|
  paths = `git ls-tree -z -r --name-only #{ref}`.split("\0")
  raise "error running git ls-tree" if !$?.success?
  paths.each do |path|
    all_paths[path] ||= Set.new
    all_paths[path] << ref
    if options[:refs].include?(ref)
      current_paths[path] ||= Set.new
      current_paths[path] << ref
    end
  end
end

# lookup of big files.
#   format:  {"<sha of blob>": {"<path>": {size: <size>, kind: <kind>}}}
#   example:
#     {
#       "b5fd415da411c030caddaf483924bceb8cdb7026" => {
#         "public/images/big.jpg" => {
#           :size => 1000000,
#           :kind => 'not-in-use',
#         },
#       },
#       "da2abbc5d64a1ad6c4c6657f29d079cdf1ad17f5" => {
#         # ...
#       },
#       # ...
#     }
# note: it's possible for a single blob to be referenced from multiple paths
big_files = {}

# populate the big_files lookup
all_revisions.each do |rev|
  `git ls-tree -z -r -l #{rev}`.split("\0").each do |line|
    raise "error running git ls-tree" if !$?.success?
    _, _, sha, size, path = line.split(/\s+/, 5)

    size = size.to_i
    next if size < options[:threshold]

    big_files[sha] ||= {}
    big_files[sha][path] ||= {size: "#{(size.to_f/MEGABYTE).round(1)}MB", kind: current_paths.has_key?(path) ? 'in-use' : 'not-in-use'}
  end
end

# print out the results
big_files.each do |sha, paths|
  paths.each do |path, details|
    kind, size = details[:kind], details[:size]

    next if kind == 'not-in-use' && options[:kind] == :"in-use"
    next if kind == 'in-use' && options[:kind] == :"not-in-use"

    print(
      options[:format] % {sha: sha, path: path, size: size, kind: kind, refs: all_paths[path].to_a.inspect} + options[:terminator]
    )
  end
end
