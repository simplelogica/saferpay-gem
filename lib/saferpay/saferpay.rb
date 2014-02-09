Dir[File.dirname(__FILE__) + '/saferpay/*.rb'].each do |file|
  require file
end

module Saferpay
  extend Configuration

  class API
    include HTTParty

    base_uri Saferpay.options[:endpoint]

    class << self

      # Check every response for errors and raise
      def perform_request(http_method, path, options, &block)
        response = super(http_method, path, options, &block)
        check_response(response)
        response
      end

      def check_response(response)
        raise Saferpay::Error.from_response(response) if response_errors?(response)
      end

      def response_errors?(response)
        response.body =~ /^ERROR: .+/ || !response.response.is_a?(Net::HTTPSuccess)
      end

    end

    # Define the same set of accessors as the Saferpay module
    attr_accessor *Configuration::VALID_CONFIG_KEYS
 
    def initialize(options = {})
      # Merge the config values from the module and those passed to the class.
      options.delete(:endpoint)
      options.delete_if { |k, v| v.nil? }
      @options = Saferpay.options.merge(options)
 
      # Copy the merged values to this client and ignore those
      # not part of our configuration
      @options.each_pair do |key, val|
        send "#{key}=", val
      end
    end

    # Returns an hash with the payment url (:payment_url key)
    # Raises an error if missing parameters
    def get_url(params = {})
      params.merge!(default_params)
      parse_get_url_response self.class.get('/CreatePayInit.asp', :query => params)
    end

    # Returns hash with parsed (and verified) response data
    # Raises an error if verification failed
    def handle_pay_confirm(request_params = {})

      # Verify data validity
      verify_resp = parse_verify_pay_confirm_response self.class.get('/VerifyPayConfirm.asp', :query => request_params.merge(default_params))

      # Parse verified callback data
      callback_data = parse_callback_data(request_params)

      verify_resp.merge(:callback_data => callback_data)
    end

    private

    def parse_get_url_response(resp)
      { :payment_url => resp.body }
    end

    def parse_verify_pay_confirm_response(resp)
      query = resp.body.split('OK:').last
      query_to_hash(query)
    end

    def parse_callback_data(params)
      normalize_params!(params)
      params[:data] = normalize_params!(HTTParty::Parser.call(params[:data], :xml)['IDP'])
      params
    end

    def default_params
      {
        'ACCOUNTID' => @options[:account_id],
      }
    end

    def query_to_hash(query)
      Hash[ query.split('&').map { |q| q.split('=').each_with_index.map { |p, i| (i == 0) ? p.downcase.to_sym : URI.decode(p) } } ]
    end

    def normalize_params!(params)
      params.replace Hash[ params.each_pair.map { |k, v| [k.downcase.to_sym, URI.decode(v).gsub('+', ' ')] } ]
    end

  end
end
