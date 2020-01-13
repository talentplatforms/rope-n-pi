# frozen_string_literal: true

require 'active_support/core_ext/hash/deep_merge'
require 'open_api_helper'

class RopenPi::Specs::OpenApiFormatter
  ::RSpec::Core::Formatters.register self, :example_group_finished, :stop

  def initialize(output, config = ::RopenPi::Specs.config)
    @output = output
    @config = config

    @output.puts 'Generating Swagger docs ...'
  end

  def example_group_finished(notification)
    metadata = notification.group.metadata

    return unless metadata.key?(:response)

    open_api_doc = @config.get_doc(metadata[:doc])
    open_api_doc.deep_merge!(metadata_to_open_api(metadata))
  end

  def stop(_notification = nil)
    @config.open_api_docs.each do |url_path, doc|
      # remove 2.0 parameters
      doc[:paths]&.each_pair do |_k, v|
        v.each_pair do |_verb, value|
          is_hash = value.is_a?(Hash)

          if is_hash && value.dig(:parameters)
            schema_param = value&.dig(:parameters)&.find { |p| p[:in] == :body && p[:schema] }

            if value && schema_param && value&.dig(:requestBody, :content, 'application/json')
              value[:requestBody][:content]['application/json'].merge!(schema: schema_param[:schema])
            end

            value[:parameters].reject! { |p| p[:in] == :body || p[:in] == :formData }
            value[:parameters].each { |p| p.delete(:type) }
            value[:headers]&.each { |p| p.delete(:type) }
          end

          value.delete(:consumes) if is_hash && value.dig(:consumes)
          value.delete(:produces) if is_hash && value.dig(:produces)
        end
      end

      file_path = File.join(@config.root_dir, url_path)
      dirname = File.dirname(file_path)
      FileUtils.mkdir_p dirname unless File.exist?(dirname)

      File.open(file_path, 'w') do |file|
        file.write(JSON.pretty_generate(doc))
      end

      @output.puts "Swagger doc generated at #{file_path}"
    end
  end

  private

  def metadata_to_open_api(metadata)
    response_code = metadata[:response][:code]
    response = metadata[:response].reject { |k, _v| k == :code }

    app_json = 'application/json'

    # need to merge in to response
    if response[:examples]&.dig(app_json)
      example = response[:examples].dig(app_json).dup
      schema = response.dig(:content, app_json, :schema)

      new_hash = { example: example }
      new_hash[:schema] = schema if schema

      response.merge!(content: { app_json => new_hash })
      response.delete(:examples)
    end

    verb = metadata[:operation][:verb]
    operation = metadata[:operation].reject { |k, _v| k == :verb }
                                    .merge(responses: { response_code => response })

    path_template = metadata[:path_item][:template]

    path_item = metadata[:path_item].reject { |k, _v| k == :template }
                                    .merge(verb => operation)

    { paths: { path_template => path_item } }
  end
end
