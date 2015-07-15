# encoding: utf-8
module Wice
  class << self
    @@model_validated = false

    # checks whether the class is a valid storage for saved queries
    def validate_query_model(query_store_model)  #:nodoc:
      unless query_store_model.respond_to?(:list)
        fail ::Wice::WiceGridArgumentError.new("Model for saving queries #{query_store_model.class.name} is invalid - there is no class method #list defined")
      end
      arit = query_store_model.method(:list).arity
      unless arit == 2
        fail ::Wice::WiceGridArgumentError.new("Method list in the model for saving queries #{query_store_model.class.name} has wrong arity - it should be 2 instead of #{arit}")
      end
      @@model_validated = true
    end

    # Retrieves and constantizes (if needed ) the Query Store model
    def get_query_store_model #:nodoc:
      query_store_model = Wice::ConfigurationProvider.value_for(:QUERY_STORE_MODEL)
      query_store_model = query_store_model.constantize if query_store_model.is_a? String
      fail ::Wice::WiceGridArgumentError.new('Defaults::QUERY_STORE_MODEL must be an ActiveRecord class or a string which can be constantized to an ActiveRecord class') unless query_store_model.is_a? Class
      validate_query_model(query_store_model) unless @@model_validated
      query_store_model
    end

    def get_string_matching_operators(model)   #:nodoc:
      if defined?(Wice::Defaults::STRING_MATCHING_OPERATORS) && (ops = Wice::ConfigurationProvider.value_for(:STRING_MATCHING_OPERATORS)) &&
         ops.is_a?(Hash) && (str_matching_operator = ops[model.connection.class.to_s])
        str_matching_operator
      else
        Wice::ConfigurationProvider.value_for(:STRING_MATCHING_OPERATOR)
      end
    end

    def deprecated_call(old_name, new_name, opts) #:nodoc:
      if opts[old_name] && !opts[new_name]
        opts[new_name] = opts[old_name]
        opts.delete(old_name)
        STDERR.puts "WiceGrid: Parameter :#{old_name} is deprecated, use :#{new_name} instead!"
      end
    end

    def log(message) #:nodoc:
      ActiveRecord::Base.logger.info('WiceGrid: ' + message)
    end
  end

  module MergeConditions #:nodoc:
    def self.included(base) #:nodoc:
      base.extend(ClassMethods)
    end

    module ClassMethods #:nodoc:
      def _sanitize_sql_hash_for_conditions(attrs, default_table_name = self.table_name)
        case connection.visitor.method(:accept).arity
        when 1
          _sanitize_sql_hash_for_conditions_before_42(attrs, default_table_name)
        when 2
          _sanitize_sql_hash_for_conditions42(attrs, default_table_name)
        else
          fail 'Unsupported Rails version'
        end
      end

      def _sanitize_sql_hash_for_conditions_before_42(attrs, default_table_name)
        attrs = expand_hash_conditions_for_aggregates(attrs)
        table = Arel::Table.new(table_name, arel_engine).alias(default_table_name)
        ActiveRecord::PredicateBuilder.build_from_hash(self, attrs, table).map do |b|
          connection.visitor.accept b
        end.join(' AND ')
      end

      def _sanitize_sql_hash_for_conditions42(attrs, default_table_name)
        attrs = ActiveRecord::PredicateBuilder.resolve_column_aliases self, attrs
        attrs = expand_hash_conditions_for_aggregates(attrs)
        table = Arel::Table.new(table_name, arel_engine).alias(default_table_name)
        ActiveRecord::PredicateBuilder.build_from_hash(self, attrs, table).map do |b|
          connection.visitor.compile b
        end.join(' AND ')
      end

      def merge_conditions(*conditions) #:nodoc:
        segments = []

        conditions.each do |condition|
          unless condition.blank?
            sql = condition.is_a?(Hash) ? _sanitize_sql_hash_for_conditions(condition) : sanitize_sql_array(condition)
            segments << sql unless sql.blank?
          end
        end

        "(#{segments.join(') AND (')})" unless segments.empty?
      end
    end
  end

  module NlMessage #:nodoc:
    class << self
      def [](key) #:nodoc:
        I18n.t(key, scope: 'wice_grid')
      end
    end
  end

  module ConfigurationProvider #:nodoc:
    class << self
      def value_for(key, strict: true) #:nodoc:
        if Wice::Defaults.const_defined?(key)
          Wice::Defaults.const_get(key)
        else
          if strict
            fail WiceGridMissingConfigurationConstantException.new("Could not find constant #{key} in the configuration file!" \
                ' It is possible that the version of WiceGrid you are using is newer than the installed configuration file in config/initializers. ' \
                "Constant Wice::Defaults::#{key} is missing  and you need to add it manually to wice_grid_config.rb or run the generator task=:\n" \
                '   rails g wice_grid:install')
          end # else nil
        end
      end
    end
  end

  module Defaults  #:nodoc:
  end

  module ExceptionsMixin  #:nodoc:
    def initialize(str)  #:nodoc:
      super('WiceGrid: ' + str)
    end
  end
  class WiceGridArgumentError < ArgumentError #:nodoc:
    include ExceptionsMixin
  end
  class WiceGridException < Exception #:nodoc:
    include ExceptionsMixin
  end
  class WiceGridMissingConfigurationConstantException < Exception #:nodoc:
    include ExceptionsMixin
  end
end
