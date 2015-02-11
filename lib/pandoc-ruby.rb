require 'open3'
require 'tempfile'

class PandocRuby

  @@pandoc_path = 'pandoc'
  @@allow_file_paths = false

  # The available readers and their corresponding names. The keys are used to
  # generate methods and specify options to Pandoc.
  READERS = {
    'native'   => 'pandoc native',
    'json'     => 'pandoc JSON',
    'markdown' => 'markdown',
    'rst'      => 'reStructuredText',
    'textile'  => 'textile',
    'html'     => 'HTML',
    'latex'    => 'LaTeX',
  }

  # The available string writers and their corresponding names. The keys are
  # used to generate methods and specify options to Pandoc.
  STRING_WRITERS = {
    'native'        => 'pandoc native',
    'json'          => 'pandoc JSON',
    'html'          => 'HTML',
    'html5'         => 'HTML5',
    's5'            => 'S5 HTML slideshow',
    'slidy'         => 'Slidy HTML slideshow',
    'dzslides'      => 'Dzslides HTML slideshow',
    'docbook'       => 'DocBook XML',
    'opendocument'  => 'OpenDocument XML',
    'latex'         => 'LaTeX',
    'beamer'        => 'Beamer PDF slideshow',
    'context'       => 'ConTeXt',
    'texinfo'       => 'GNU Texinfo',
    'man'           => 'groff man',
    'markdown'      => 'markdown',
    'plain'         => 'plain',
    'rst'           => 'reStructuredText',
    'mediawiki'     => 'MediaWiki markup',
    'textile'       => 'textile',
    'rtf'           => 'rich text format',
    'org'           => 'emacs org mode',
    'asciidoc'      => 'asciidoc'
  }

  # The available binary writers and their corresponding names. The keys are
  # used to generate methods and specify options to Pandoc.
  BINARY_WRITERS = {
    'odt'   => 'OpenDocument',
    'docx'  => 'Word docx',
    'epub'  => 'EPUB V2',
    'epub3' => 'EPUB V3'
  }

  # All of the available Writers.
  WRITERS = STRING_WRITERS.merge(BINARY_WRITERS)

  # To use run the pandoc command with a custom executable path, the path
  # to the pandoc executable can be set here.
  def self.pandoc_path=(path)
    @@pandoc_path = path
  end

  # Pandoc can also be used with a file path as the first argument. For
  # security reasons, this is disabled by default, but it can be enabled by
  # setting this to `true`.
  def self.allow_file_paths=(value)
    @@allow_file_paths = value
  end

  # A shortcut method that creates a new PandocRuby object and immediately
  # calls `#convert`. Options passed to this method are passed directly to
  # `#new` and treated the same as if they were passed directly to the
  # initializer.
  def self.convert(*args)
    new(*args).convert
  end

  attr_accessor :options
  def options; @options || [] end

  attr_accessor :option_string
  def option_string; @option_string || '' end

  attr_accessor :binary_output
  def binary_output; @binary_output || false end

  attr_accessor :writer
  def writer; @writer || 'html' end

  # Create a new PandocRuby converter object. The first argument should be the
  # string that will be converted or, if `.allow_file_paths` has been set to
  # `true`, this can also be a path to a file (or an array of file paths). The
  # executable name can be used as the second argument, but will default to
  # `pandoc` if the second argument is omitted or anything other than an
  # executable name. Any other arguments will be converted to pandoc options.
  def initialize(*args)
    target = args.shift
    @target = if @@allow_file_paths && target.is_a?(String) && File.exists?(target)
      File.read(target)
    elsif @@allow_file_paths && target.is_a?(Array)
      target_strings = []
      target.each do | file_path |
        target_strings << File.read(file_path)
      end
      target_strings.join("\n\n")
    else
      target rescue target
    end
    self.options = args
  end

  # Run the conversion. The convert method can take any number of arguments,
  # which will be converted to pandoc options. If options were already
  # specified in an initializer or reader method, they will be combined with
  # any that are passed to this method.
  #
  # Returns a string with the converted content.
  #
  # Example:
  #
  #   PandocRuby.new("# text").convert
  #   # => "<h1 id=\"text\">text</h1>\n"
  def convert(*args)
    self.options += args if args
    self.option_string = prepare_options(self.options)
    if self.binary_output
      convert_binary
    else
      convert_string
    end
  end
  alias_method :to_s, :convert

  # Generate class methods for each of the readers in PandocRuby::READERS.
  # When one of these methods is called, it simply calls the initializer
  # with the `from` option set to the reader key, and returns the object.
  #
  # Example:
  #
  #   PandocRuby.markdown("# text")
  #   # => #<PandocRuby:0x007 @target="# text", @options=[{:from=>"markdown"}]
  class << self
    READERS.each_key do |r|
      define_method(r) do |*args|
        args += [{:from => r}]
        new(*args)
      end
    end
  end

  # Generate instance methods for each of the writers in PandocRuby::WRITERS.
  # When one of these methods is called, it simply calls the `#convert` method
  # with the `to` option set to the writer key, thereby returning the
  # converted string.
  #
  # Example:
  #
  #   PandocRuby.new("# text").to_html
  #   # => "<h1 id=\"text\">text</h1>\n"
  WRITERS.each_key do |w|
    define_method(:"to_#{w}") do |*args|
      args += [{:to => w.to_sym}]
      convert(*args)
    end
  end

private

  # Executes the pandoc command for binary writers. A temp file is created
  # and written to, then read back into the program as a string, then the
  # temp file is closed and unlinked.
  def convert_binary
    tmp_file = Tempfile.new('pandoc-conversion')
    begin
      self.options += [{:output => tmp_file.path}]
      self.option_string =  "#{self.option_string} --output #{tmp_file.path}"
      execute(command_with_options)
      return IO.binread(tmp_file)
    ensure
      tmp_file.close
      tmp_file.unlink
    end
  end

  # Executes the pandoc command for btring writers.
  def convert_string
    execute(command_with_options)
  end

  # Combines the executable string with the option string.
  def command_with_options
    @@pandoc_path + self.option_string
  end

  # Runs the command and returns the output.
  def execute(command)
    output = error = exit_status = nil
    Open3::popen3(command) do |stdin, stdout, stderr, wait_thr|
      stdin.puts @target
      stdin.close
      output = stdout.read
      error = stderr.read
      exit_status = wait_thr.value
    end
    raise error unless exit_status.success?
    output
  end

  # Builds the option string to be passed to pandoc by iterating over the
  # opts passed in. Recursively calls itself in order to handle hash options.
  def prepare_options(opts = [])
    opts.inject('') do |string, (option, value)|
      string += case
                when value
                  create_option(option, value)
                when option.respond_to?(:each_pair)
                  prepare_options(option)
                else
                  create_option(option)
                end
    end
  end

  # Takes a flag and optional argument, uses it to set any relevant options
  # used by the library, and returns string with the option formatted as a
  # command line options. If the option has an argument, it is also included.
  def create_option(flag, argument = nil)
    return if !flag
    flag = flag.to_s
    set_pandoc_ruby_options(flag, argument)
    if !!argument
      "#{format_flag(flag)} #{argument}"
    else
      format_flag(flag)
    end
  end

  # Formats an option flag in order to be used with the pandoc command line
  # tool.
  def format_flag(flag)
    if flag.length == 1
      " -#{flag}"
    else
      " --#{flag.to_s.gsub(/_/, '-')}"
    end
  end

  # Takes an option and optional argument and uses them to set any flags
  # used by PandocRuby.
  def set_pandoc_ruby_options(flag, argument = nil)
    if flag == 't' || flag == 'to'
      self.writer = argument.to_s
      self.binary_output = true if BINARY_WRITERS.keys.include?(self.writer)
    end
  end

end
