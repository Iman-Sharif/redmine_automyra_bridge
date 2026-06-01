# frozen_string_literal: true

module WikiHub
  # Phase 4: Template Variable Processing Service
  # Handles {{variable_name}} syntax in templates with default values
  class TemplateVariableService
    VARIABLE_REGEX = /\{\{\s*(\w+)\s*(?::\s*"([^"]*)")?\s*\}\}/
    MAX_CONTENT_LENGTH = 100_000
    
    # Extract variables from template content
    def self.extract_variables(content)
      return [] if content.blank?
      validate_content_size!(content)
      
      variables = []
      content.scan(VARIABLE_REGEX) do |name, default|
        variables << {
          name: name,
          default: default,
          required: default.nil?
        }
      end
      variables.uniq { |v| v[:name] }
    end
    
    # Process template with provided values
    def self.process_template(content, values = {})
      return content if content.blank?
      validate_content_size!(content)
      
      content.gsub(VARIABLE_REGEX) do |match|
        name = $1
        default = $2
        
        # Use provided value, fallback to default, or keep placeholder
        values[name] || default || match
      end
    end
    
    # Validate that all required variables are provided
    def self.validate_variables(content, values = {})
      validate_content_size!(content) unless content.blank?
      variables = extract_variables(content)
      missing = variables.select { |v| v[:required] && values[v[:name]].blank? }
      
      {
        valid: missing.empty?,
        missing: missing.map { |v| v[:name] },
        all_variables: variables.map { |v| v[:name] }
      }
    end
    
    # Generate form fields for template variables
    def self.variable_form_fields(content)
      validate_content_size!(content) unless content.blank?
      variables = extract_variables(content)
      
      variables.map do |var|
        {
          name: var[:name],
          label: var[:name].humanize,
          required: var[:required],
          default: var[:default],
          type: guess_field_type(var[:name])
        }
      end
    end
    
    private
    
    def self.guess_field_type(name)
      case name.downcase
      when /date/
        'date'
      when /email/
        'email'
      when /url|link/
        'url'
      when /description|content|body|text/
        'textarea'
      else
        'text'
      end
    end

    def self.validate_content_size!(content)
      return if content.to_s.bytesize <= MAX_CONTENT_LENGTH

      raise ArgumentError, 'Template content exceeds maximum supported size'
    end
  end
end
