# Copyright (C) 2011-2017 American Registry for Internet Numbers
#
# Permission to use, copy, modify, and/or distribute this software for any
# purpose with or without fee is hereby granted, provided that the above
# copyright notice and this permission notice appear in all copies.
#
# THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
# WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
# MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
# ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
# WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
# ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF OR
# IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.


require 'fileutils'
require 'time'
require 'yaml'
require 'ostruct'
require 'nicinfo/nicinfo_logger'
require 'nicinfo/factory'
require 'nicinfo/constants'

module NicInfo

  # Handles configuration of the application
  class Config

    attr_accessor :logger, :config, :rdap_cache_dir, :options, :conf_msgs, :rdap_bootstrap_dir, :factory

    # Intializes the configuration with a place to look for the config file
    # If the file doesn't exist, a default is used.
    # Main routines will do something like NicInfo::Config.new( NicInfo::Config.formulate_app_data_dir() )
    def initialize app_data

      @options = OpenStruct.new
      @app_data = app_data
      @logger = NicInfo::Logger.new
      @conf_msgs = Array.new
      @factory = NicInfo::Factory.new( self )

      config_file_name = Config.formulate_config_file_name( @app_data )
      if File.exist?( config_file_name )
        @config = load_config( config_file_name )
      else
        @config = YAML.load( @@yaml_config )
      end

      configure_logger()

    end

    # Setups work space for the application and lays down default config
    # If directory is nil, then it uses its own value
    def setup_workspace

      @rdap_bootstrap_dir = File.join( @app_data, NicInfo::BOOTSTRAP_FILE_DIR )
      if ! File.exist?( @app_data )

        @logger.trace "Creating configuration in " + @app_data
        Dir.mkdir( @app_data )
        f = File.open( Config.formulate_config_file_name( @app_data ), "w" )
        f.puts @@yaml_config
        f.close

        @rdap_cache_dir = File.join( @app_data, "rdap_cache" )
        Dir.mkdir( @rdap_cache_dir )

        copy_bsfiles

      else

        if @options.reset_config
          config_file_name = Config.formulate_config_file_name( @app_data )
          @logger.trace "Resetting configuration in " + config_file_name
          f = File.open( config_file_name, "w" )
          f.puts @@yaml_config
          f.close
          @config = YAML.load( File.open( config_file_name ) )
          @logger.trace "Resetting bootstrap files in " + @rdap_bootstrap_dir
          begin
            FileUtils::rm_r( @rdap_bootstrap_dir )
          rescue Errno::ENOENT
            # do nothing
          end
          copy_bsfiles
        end
        @logger.trace "Using configuration found in " + @app_data
        @rdap_cache_dir = File.join( @app_data, "rdap_cache" )

      end

    end

    def check_config_version
      # check to see if the configuration is old
      config_section = @config[NicInfo::CONFIG]
      if config_section != nil
        config_version = config_section[NicInfo::VERSION_CONFIG]
      end
      if config_version == nil || config_version < NicInfo::CONFIG_VERSION
        # if a reset hasn't been asked for
        if !@options.reset_config
          @logger.mesg( "Your configuration is old. Use --reset to create a new one.", NicInfo::AttentionType::ERROR )
        end
      end
    end

    def load_config config_file_name
      @config = YAML.load( @@yaml_config )
      @config[NicInfo::CONFIG].delete(NicInfo::VERSION_CONFIG)
      merger = proc do |key, v1, v2|
        Hash === v1 && Hash === v2 ? v1.merge(v2, &merger) :
                Array === v1 && Array === v2 ? v1 | v2 :
                        [:undefined, nil, :nil].include?(v2) ? v1 : v2
      end
      @config.merge!( YAML.load( File.open( config_file_name ) ), &merger )
    end

    def copy_bsfiles
      src_dir = File.join( File.dirname( __FILE__ ), NicInfo::BOOTSTRAP_FILE_DIR )
      FileUtils::cp_r( src_dir, @rdap_bootstrap_dir )
    end

    def set_bsfiles_last_update_time t = Time.now
      f = File.open(bsfiles_last_update_filename, "w" )
      f.write t.strftime( "%Y-%m-%d %H:%M:%S")
      f.close
    end

    def get_bsfiles_last_update_time
      retval = nil
      fname = bsfiles_last_update_filename
      if File.exist?( fname )
        f = File.open( fname, "r" )
        data = f.read
        f.close
        retval = Time.parse( data )
      end
      return retval
    end

    def bsfiles_last_update_filename
      File.join(@rdap_bootstrap_dir, NicInfo::BSFILE_LAST_CHECK_FILENAME)
    end

    def check_bsfiles_age?
      retval = false
      if @config[ NicInfo::BOOTSTRAP ][ NicInfo::CHECK_BSFILES_AGE ]
        t = get_bsfiles_last_update_time
        if t != nil
          configed_age = @config[ NicInfo::BOOTSTRAP ][ NicInfo::BSFILES_AGE ]
          age = t + configed_age
          retval = true if age < Time.now
        else
          retval = true
        end
      end
      return retval
    end

    def update_bsfiles? aged
      return aged && @config[ NicInfo::BOOTSTRAP ][ NicInfo::UPDATE_BSFILES ]
    end

    def save name, data
      data_file = File.open( File.join( @app_data, name ), "w" )
      data_file.write data
      data_file.close
    end

    def save_as_yaml name, obj
      data_file = File.open( File.join( @app_data, name ), "w" )
      data_file.puts YAML::dump(obj)
      data_file.close
    end

    def load name
      data_file = File.open( File.join( @app_data, name ), "r" )
      retval = data_file.read
      data_file.close
      return retval
    end

    def load_as_yaml name, default = nil
      file_name = make_file_name( name )
      retval = default
      if File.exist?( file_name )
        data_file = File.open( File.join( @app_data, name ), "r" )
        retval = YAML::load( data_file, permitted_classes: [NicInfo::DataTree,NicInfo::Logger,NicInfo::DataNode,IO,Rainbow::Wrapper], aliases: true )
        data_file.close
      elsif default == nil
        raise "#{file_name} does not exist"
      end
      return retval
    end

    def make_file_name name
      File.join( @app_data, name )
    end

    # Configures the logger
    def configure_logger
      output = @config[ NicInfo::OUTPUT ]
      return if output == nil

      @logger.message_level = output[ NicInfo::MESSAGES ]
      @logger.validate_message_level

      messages_file = output[ NicInfo::MESSAGES_FILE ]
      if messages_file != nil
        @logger.message_out = File.open( messages_file, "w+" )
      end

      @logger.data_amount = output[ NicInfo::DATA ]
      @logger.validate_data_amount

      data_file = output[ NicInfo::DATA_FILE ]
      if data_file != nil
        @logger.data_out= File.open( data_file, "w+" )
      end

      @logger.pager=output[ NicInfo::PAGER ]
      @logger.auto_wrap=output[ NicInfo::AUTO_WRAP ]
      @logger.default_width=output[ NicInfo::DEFAULT_WIDTH ]
      @logger.detect_width=output[ NicInfo::DETECT_WIDTH ]

      @logger.color_scheme = output[ NicInfo::COLOR_SCHEME ]
      @logger.validate_color_scheme
    end

    def self.clean

      FileUtils::rm_r( formulate_app_data_dir() )

    end

    def self.formulate_app_data_dir
      if Gem.win_platform?
        data_dir = File.join(ENV['APPDATA'], "NicInfo")
      elsif RUBY_PLATFORM =~ /linux/
        data_dir = File.join(ENV['HOME'], ".NicInfo")
      elsif RUBY_PLATFORM =~ /darwin/
        data_dir = File.join(ENV['HOME'], ".NicInfo")
      elsif RUBY_PLATFORM =~ /freebsd/
        data_dir = File.join(ENV['HOME'], ".NicInfo")
      elsif RUBY_PLATFORM =~ /cygwin/
        data_dir = File.join(ENV['HOME'], ".NicInfo")
      else
        raise ScriptError, "system platform is not recognized."
      end
      return data_dir
    end

    def self.formulate_config_file_name data_dir
      File.join( data_dir, "config.yaml" )
    end

    @@yaml_config = <<YAML_CONFIG
output:

  # possible values are NONE, SOME, ALL
  messages: SOME

  # If specified, messages goes to this file
  # otherwise, leave it commented out to go to stderr
  #messages_file: /tmp/NicInfo.messages

  # possible values are TERSE, NORMAL, EXTRA
  data: NORMAL

  # If specified, data goest to this file
  # otherwise, leave it commented out to go to stdout
  #data_file: /tmp/NicInfo.data

  # Page output with system pager when appropriate.
  pager: true

  # Automatically wrap text when possible.
  auto_wrap: true

  # When auto wrapping, automatically determine the terminal
  # width if possible
  detect_width: true

  # The default terminal width if it is not to be detected
  # or cannot be detected
  default_width: 80

  # The color scheme to use. Possible values are
  # - DARK for terminals with dark background
  # - LIGHT for terminals with light background
  # - NONE for no color
  # color is turned off automatically if a pager is used and the pager is not 'less'.
  color_scheme: DARK

cache:

  # The maximum age an item from the cache will be used.
  # This value is in seconds
  cache_expiry: 3600

  # The maximum age an item will be in the cache before it is evicted
  # when the cache is cleaned.
  # This value is in seconds
  cache_eviction: 604800

  # Use the cache.
  # Values are true or false
  use_cache: true

  # Automatically clean the cache.
  clean_cache: true

bootstrap:

  # The base or bootstrap URL. Specifying this will bypass all built-in bootstrapping.
  #base_url: https://rdap-bootstrap.arin.net/bootstrap

  help_root_url: https://rdap-bootstrap.arin.net/bootstrap

  entity_root_url: https://rdap.arin.net/registry

  ip_root_url: https://rdap.arin.net/registry

  as_root_url: https://rdap.arin.net/registry

  domain_root_url: https://rdap.arin.net/registry

  ns_root_url: https://rdap.arin.net/registry

  # Check for updates of the IANA RDAP bootstrap files
  # If true, check for IANA bootstrap files once they have aged past bsfiles_age
  # Values are true or false
  check_bsfiles_age: true 

  # The age at which IANA RDAP bootstrap files are to be checked if check_bsfiles is true
  # This value is in seconds
  bsfiles_age: 604800

  # If the age of the IANA RDAP bootstrap files are considered old according to bsfiles_age
  # and check_bsfiles is true, then this value will cause a fetch of new files if true.
  # Values are true or false
  update_bsfiles: true

search:

  # Substring matching
  # NOT YET USED
  substring: true

security:

  # if HTTPS cannot be established, try HTTP
  try_insecure: true

config:
  # This should not be altered.
  version: 4

YAML_CONFIG

  end

end
