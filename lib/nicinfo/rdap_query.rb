# Copyright (C) 2018 American Registry for Internet Numbers
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

module NicInfo

  class RDAPResponse

    attr_accessor :data, :json_data, :exception, :error_state, :response, :code

  end

  class RDAPQuery

    attr_accessor :config

    def initialize( config )
      @config = config
    end

    def do_rdap_query
      retval = nil
      if @config.config[ NicInfo::BOOTSTRAP ][ NicInfo::BOOTSTRAP_URL ] == nil && !@config.options.url
        bootstrap = Bootstrap.new( @config )
        qtype = @config.options.query_type
        if qtype == QueryType::BY_SERVER_HELP
          qtype = guess_query_value_type( @config.options.argv )
        end
        case qtype
          when QueryType::BY_IP4_ADDR
            @config.config[ NicInfo::BOOTSTRAP ][ NicInfo::BOOTSTRAP_URL ] = bootstrap.find_url_by_ip( @config.options.argv[ 0 ] )
          when QueryType::BY_IP6_ADDR
            @config.config[ NicInfo::BOOTSTRAP ][ NicInfo::BOOTSTRAP_URL ] = bootstrap.find_url_by_ip( @config.options.argv[ 0 ] )
          when QueryType::BY_IP4_CIDR
            @config.config[ NicInfo::BOOTSTRAP ][ NicInfo::BOOTSTRAP_URL ] = bootstrap.find_url_by_ip( @config.options.argv[ 0 ] )
          when QueryType::BY_IP6_CIDR
            @config.config[ NicInfo::BOOTSTRAP ][ NicInfo::BOOTSTRAP_URL ] = bootstrap.find_url_by_ip( @config.options.argv[ 0 ] )
          when QueryType::BY_AS_NUMBER
            @config.config[ NicInfo::BOOTSTRAP ][ NicInfo::BOOTSTRAP_URL ] = bootstrap.find_url_by_as( @config.options.argv[ 0 ] )
          when QueryType::BY_DOMAIN
            @config.config[ NicInfo::BOOTSTRAP ][ NicInfo::BOOTSTRAP_URL ] = bootstrap.find_url_by_domain( @config.options.argv[ 0 ] )
          when QueryType::BY_NAMESERVER
            @config.config[ NicInfo::BOOTSTRAP ][ NicInfo::BOOTSTRAP_URL ] = bootstrap.find_url_by_domain( @config.options.argv[ 0 ] )
          when QueryType::BY_ENTITY_HANDLE
            @config.config[ NicInfo::BOOTSTRAP ][ NicInfo::BOOTSTRAP_URL ] = bootstrap.find_url_by_entity( @config.options.argv[ 0 ] )
          when QueryType::SRCH_ENTITY_BY_NAME
            @config.config[ NicInfo::BOOTSTRAP ][ NicInfo::BOOTSTRAP_URL ] = @config.config[ NicInfo::BOOTSTRAP ][ NicInfo::ENTITY_ROOT_URL ]
          when QueryType::SRCH_DOMAIN_BY_NAME
            @config.config[ NicInfo::BOOTSTRAP ][ NicInfo::BOOTSTRAP_URL ] = bootstrap.find_url_by_domain( @config.options.argv[ 0 ] )
          when QueryType::SRCH_DOMAIN_BY_NSNAME
            @config.config[ NicInfo::BOOTSTRAP ][ NicInfo::BOOTSTRAP_URL ] = bootstrap.find_url_by_domain( @config.options.argv[ 0 ] )
          when QueryType::SRCH_DOMAIN_BY_NSIP
            @config.config[ NicInfo::BOOTSTRAP ][ NicInfo::BOOTSTRAP_URL ] = @config.config[ NicInfo::BOOTSTRAP ][ NicInfo::DOMAIN_ROOT_URL ]
          when QueryType::SRCH_NS_BY_NAME
            @config.config[ NicInfo::BOOTSTRAP ][ NicInfo::BOOTSTRAP_URL ] = bootstrap.find_url_by_domain( @config.options.argv[ 0 ] )
          when QueryType::SRCH_NS_BY_IP
            @config.config[ NicInfo::BOOTSTRAP ][ NicInfo::BOOTSTRAP_URL ] = bootstrap.find_url_by_ip( @config.options.argv[ 0 ] )
          else
            @config.config[ NicInfo::BOOTSTRAP ][ NicInfo::BOOTSTRAP_URL ] = @config.config[ NicInfo::BOOTSTRAP ][ NicInfo::HELP_ROOT_URL ]
        end
      end
      begin
        rdap_url = nil
        unless @config.options.url
          path = create_resource_url(@config.options.argv, @config.options.query_type)
          rdap_url = make_rdap_url(@config.config[NicInfo::BOOTSTRAP][NicInfo::BOOTSTRAP_URL], path)
        else
          rdap_url = @config.options.argv[0]
        end
        data = get( rdap_url, 0 )
        json_data = JSON.load data
        if (ec = json_data[ NicInfo::NICINFO_DEMO_ERROR ]) != nil
          res = MyHTTPResponse.new( "1.1", ec, "Demo Exception" )
          res["content-type"] = NicInfo::RDAP_CONTENT_TYPE
          res.body=data
          raise Net::HTTPServerException.new( "Demo Exception", res )
        end
        inspect_rdap_compliance json_data
        cache_self_references json_data
        retval = json_data
      rescue JSON::ParserError => a
        @config.logger.mesg( "Server returned invalid JSON!", NicInfo::AttentionType::ERROR )
      rescue SocketError => a
        @config.logger.mesg(a.message, NicInfo::AttentionType::ERROR )
      rescue ArgumentError => a
        @config.logger.mesg(a.message, NicInfo::AttentionType::ERROR )
      rescue Net::HTTPServerException => e
        case e.response.code
          when "200"
            @config.logger.mesg( e.message, NicInfo::AttentionType::SUCCESS )
          when "401"
            @config.logger.mesg("Authorization is required.", NicInfo::AttentionType::ERROR )
            handle_error_response e.response
          when "404"
            @config.logger.mesg("Query yielded no results.", NicInfo::AttentionType::INFO )
            handle_error_response e.response
          else
            @config.logger.mesg("Error #{e.response.code}.", NicInfo::AttentionType::ERROR )
            handle_error_response e.response
        end
        @config.logger.trace("Server response code was " + e.response.code)
      rescue Net::HTTPFatalError => e
        case e.response.code
          when "500"
            @config.logger.mesg("RDAP server is reporting an internal error.", NicInfo::AttentionType::ERROR )
            handle_error_response e.response
          when "501"
            @config.logger.mesg("RDAP server does not implement the query.", NicInfo::AttentionType::ERROR )
            handle_error_response e.response
          when "503"
            @config.logger.mesg("RDAP server is reporting that it is unavailable.", NicInfo::AttentionType::ERROR )
            handle_error_response e.response
          else
            @config.logger.mesg("Error #{e.response.code}.", NicInfo::AttentionType::ERROR )
            handle_error_response e.response
        end
        @config.logger.trace("Server response code was " + e.response.code)
      rescue Net::HTTPRetriableError => e
        @config.logger.mesg("Too many redirections, retries, or a redirect loop has been detected." )
      end

      return retval
    end

    # Creates a query from a query type
    def create_resource_url(args, queryType)

      path = ""
      case queryType
        when QueryType::BY_IP4_ADDR
          path << "ip/" << args[0]
        when QueryType::BY_IP6_ADDR
          path << "ip/" << args[0]
        when QueryType::BY_IP4_CIDR
          path << "ip/" << args[0]
        when QueryType::BY_IP6_CIDR
          path << "ip/" << args[0]
        when QueryType::BY_AS_NUMBER
          path << "autnum/" << args[0]
        when QueryType::BY_NAMESERVER
          path << "nameserver/" << args[0]
        when QueryType::BY_DOMAIN
          path << "domain/" << args[0]
        when QueryType::BY_RESULT
          tree = @config.load_as_yaml(NicInfo::ARININFO_LASTTREE_YAML)
          path = tree.find_rest_ref(args[0])
          raise ArgumentError.new("Unable to find result for " + args[0]) unless path
        when QueryType::BY_ENTITY_HANDLE
          path << "entity/" << URI.escape( args[ 0 ] )
        when QueryType::SRCH_ENTITY_BY_NAME
          case args.length
            when 1
              path << "entities?fn=" << URI.escape( args[ 0 ] )
            when 2
              path << "entities?fn=" << URI.escape( args[ 0 ] + " " + args[ 1 ] )
            when 3
              path << "entities?fn=" << URI.escape( args[ 0 ] + " " + args[ 1 ] + " " + args[ 2 ] )
          end
        when QueryType::SRCH_DOMAIN_BY_NAME
          path << "domains?name=" << args[ 0 ]
        when QueryType::SRCH_DOMAIN_BY_NSNAME
          path << "domains?nsLdhName=" << args[ 0 ]
        when QueryType::SRCH_DOMAIN_BY_NSIP
          path << "domains?nsIp=" << args[ 0 ]
        when QueryType::SRCH_NS_BY_NAME
          path << "nameservers?name=" << args[ 0 ]
        when QueryType::SRCH_NS_BY_IP
          path << "nameservers?ip=" << args[ 0 ]
        when QueryType::BY_SERVER_HELP
          path << "help"
        else
          raise ArgumentError.new("Unable to create a resource URL for " + queryType)
      end

      return path
    end

    def make_rdap_url( base_url, resource_path )
      unless base_url.end_with?("/")
        base_url << "/"
      end
      base_url << resource_path
    end

    # Do an HTTP GET with the path.
    def get url, try, expect_rdap = true

      data = @cache.get(url)
      if data == nil

        @config.logger.trace("Issuing GET for " + url)
        uri = URI.parse( URI::encode( url ) )
        req = Net::HTTP::Get.new(uri.request_uri)
        req["User-Agent"] = NicInfo::VERSION_LABEL
        req["Accept"] = NicInfo::RDAP_CONTENT_TYPE + ", " + NicInfo::JSON_CONTENT_TYPE
        req["Connection"] = "close"
        http = Net::HTTP.new( uri.host, uri.port )
        if uri.scheme == "https"
          http.use_ssl=true
          http.verify_mode=OpenSSL::SSL::VERIFY_NONE
        end

        begin
          res = http.start do |http_req|
            http_req.request(req)
          end
        rescue OpenSSL::SSL::SSLError => e
          if @config.config[ NicInfo::SECURITY ][ NicInfo::TRY_INSECURE ]
            @config.logger.mesg( "Secure connection failed. Trying insecure connection." )
            uri.scheme = "http"
            return get( uri.to_s, try, expect_rdap )
          else
            raise e
          end
        end

        case res
          when Net::HTTPSuccess
            content_type = res[ "content-type" ].downcase
            if expect_rdap
              unless content_type.include?(NicInfo::RDAP_CONTENT_TYPE) or content_type.include?(NicInfo::JSON_CONTENT_TYPE)
                raise Net::HTTPServerException.new("Bad Content Type", res)
              end
              if content_type.include? NicInfo::JSON_CONTENT_TYPE
                @config.conf_msgs << "Server responded with non-RDAP content type but it is JSON"
              end
            end
            data = res.body
            @cache.create_or_update(url, data)
          else
            if res.code == "301" or res.code == "302" or res.code == "303" or res.code == "307" or res.code == "308"
              res.error! if try >= 5
              location = res["location"]
              return get( location, try + 1, expect_rdap)
            end
            res.error!
        end #end case

      end #end if

      return data

    end #end def

    def handle_error_response (res)
      if res["content-type"] == NicInfo::RDAP_CONTENT_TYPE && res.body && res.body.to_s.size > 0
        json_data = JSON.load( res.body )
        inspect_rdap_compliance json_data
        @config.factory.new_notices.display_notices json_data, true
        @config.factory.new_error_code.display_error_code( json_data )
      end
    end

    def inspect_rdap_compliance json
      rdap_conformance = json[ "rdapConformance" ]
      if rdap_conformance
        rdap_conformance.each do |conformance|
          @config.logger.trace( "Server conforms to #{conformance}", NicInfo::AttentionType::SECONDARY )
        end
      else
        @config.conf_msgs << "Response has no RDAP Conformance level specified."
      end
    end

    def cache_self_references json_data
      links = NicInfo::get_links json_data, @config
      if links
        self_link = NicInfo.get_self_link links
        if self_link
          pretty = JSON::pretty_generate( json_data )
          @cache.create( self_link, pretty )
        end
      end
      entities = NicInfo::get_entitites json_data
      entities.each do |entity|
        cache_self_references( entity )
      end if entities
      nameservers = NicInfo::get_nameservers json_data
      nameservers.each do |ns|
        cache_self_references( ns )
      end if nameservers
      ds_data_objs = NicInfo::get_ds_data_objs json_data
      ds_data_objs.each do |ds|
        cache_self_references( ds )
      end if ds_data_objs
      key_data_objs = NicInfo::get_key_data_objs json_data
      key_data_objs.each do |key|
        cache_self_references( key )
      end if key_data_objs
    end

  end

  class RDAPQueryGuess

    attr_accessor :config

    def initialize( config )
      @config = config
    end

    # Evaluates the args and guesses at the type of query.
    # Args is an array of strings, most likely what is left
    # over after parsing ARGV
    def guess_query_value_type(args)
      retval = nil

      if args.length() == 1

        case args[0]
          when NicInfo::URL_REGEX
            retval = QueryType::BY_URL
          when NicInfo::IPV4_REGEX
            retval = QueryType::BY_IP4_ADDR
          when NicInfo::IPV6_REGEX
            retval = QueryType::BY_IP6_ADDR
          when NicInfo::IPV6_HEXCOMPRESS_REGEX
            retval = QueryType::BY_IP6_ADDR
          when NicInfo::AS_REGEX
            retval = QueryType::BY_AS_NUMBER
          when NicInfo::ASN_REGEX
            old = args[0]
            args[0] = args[0].sub(/^AS/i, "")
            @config.logger.trace("Interpretting " + old + " as autonomous system number " + args[0])
            retval = QueryType::BY_AS_NUMBER
          when NicInfo::IP4_ARPA
            retval = QueryType::BY_DOMAIN
          when NicInfo::IP6_ARPA
            retval = QueryType::BY_DOMAIN
          when /(.*)\/\d/
            ip = $+
            if ip =~ NicInfo::IPV4_REGEX
              retval = QueryType::BY_IP4_CIDR
            elsif ip =~ NicInfo::IPV6_REGEX || ip =~ NicInfo::IPV6_HEXCOMPRESS_REGEX
              retval = QueryType::BY_IP6_CIDR
            end
          when NicInfo::DATA_TREE_ADDR_REGEX
            retval = QueryType::BY_RESULT
          when NicInfo::NS_REGEX
            retval = QueryType::BY_NAMESERVER
          when NicInfo::DOMAIN_REGEX
            retval = QueryType::BY_DOMAIN
          when NicInfo::ENTITY_REGEX
            retval = QueryType::BY_ENTITY_HANDLE
          else
            last_name = args[ 0 ].sub( /\*/, '' ).upcase
            if NicInfo::is_last_name( last_name )
              retval = QueryType::SRCH_ENTITY_BY_NAME
            end
        end

      elsif args.length() == 2

        last_name = args[ 1 ].sub( /\*/, '' ).upcase
        first_name = args[ 0 ].sub( /\*/, '' ).upcase
        if NicInfo::is_last_name(last_name) && (NicInfo::is_male_name(first_name) || NicInfo::is_female_name(first_name))
          retval = QueryType::SRCH_ENTITY_BY_NAME
        end

      elsif args.length() == 3

        last_name = args[ 2 ].sub( /\*/, '' ).upcase
        first_name = args[ 0 ].sub( /\*/, '' ).upcase
        if NicInfo::is_last_name(last_name) && (NicInfo::is_male_name(first_name) || NicInfo::is_female_name(first_name))
          retval = QueryType::SRCH_ENTITY_BY_NAME
        end

      end

      return retval
    end

  end

end
