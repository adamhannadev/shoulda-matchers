module Shoulda # :nodoc:
  module Matchers
    module ActiveRecord # :nodoc:
      # Ensure that the belongs_to relationship exists.
      #
      # Options:
      # * <tt>:class_name</tt> - tests that the association resolves to class_name.
      # * <tt>:validate</tt> - tests that the association makes use of the validate
      # option.
      # * <tt>:touch</tt> - tests that the association makes use of the touch
      # option.
      #
      # Example:
      #   it { should belong_to(:parent) }
      #
      def belong_to(name)
        AssociationMatcher.new(:belongs_to, name)
      end

      # Ensures that the has_many relationship exists.  Will also test that the
      # associated table has the required columns.  Works with polymorphic
      # associations.
      #
      # Options:
      # * <tt>through</tt> - association name for <tt>has_many :through</tt>
      # * <tt>dependent</tt> - tests that the association makes use of the
      #   dependent option.
      # * <tt>:class_name</tt> - tests that the association resoves to class_name.
      # * <tt>:validate</tt> - tests that the association makes use of the validate
      # option.
      #
      # Example:
      #   it { should have_many(:friends) }
      #   it { should have_many(:enemies).through(:friends) }
      #   it { should have_many(:enemies).dependent(:destroy) }
      #
      def have_many(name)
        AssociationMatcher.new(:has_many, name)
      end

      # Ensure that the has_one relationship exists.  Will also test that the
      # associated table has the required columns.  Works with polymorphic
      # associations.
      #
      # Options:
      # * <tt>:dependent</tt> - tests that the association makes use of the
      #   dependent option.
      # * <tt>:class_name</tt> - tests that the association resolves to class_name.
      # * <tt>:validate</tt> - tests that the association makes use of the validate
      # option.
      #
      # Example:
      #   it { should have_one(:god) } # unless hindu
      #
      def have_one(name)
        AssociationMatcher.new(:has_one, name)
      end

      # Ensures that the has_and_belongs_to_many relationship exists, and that
      # the join table is in place.
      #
      # Options:
      # * <tt>:class_name</tt> - tests that the association resolves to class_name.
      # * <tt>:validate</tt> - tests that the association makes use of the validate
      # option.
      #
      # Example:
      #   it { should have_and_belong_to_many(:posts) }
      #
      def have_and_belong_to_many(name)
        AssociationMatcher.new(:has_and_belongs_to_many, name)
      end

      class AssociationMatcher # :nodoc:
        def initialize(macro, name)
          @macro = macro
          @name = name
          @options = {}
          @submatchers = []
          @missing = ''
        end

        def through(through)
          through_matcher = AssociationMatchers::ThroughMatcher.new(through, @name)
          add_submatcher(through_matcher)
          self
        end

        def dependent(dependent)
          dependent_matcher = AssociationMatchers::DependentMatcher.new(dependent, @name)
          add_submatcher(dependent_matcher)
          self
        end

        def order(order)
          order_matcher = AssociationMatchers::OrderMatcher.new(order, @name)
          add_submatcher(order_matcher)
          self
        end

        def add_submatcher(matcher)
          @submatchers << matcher
        end

        def submatchers_match?
          failing_submatchers.empty?
        end

        def submatcher_failure_messages
          failing_submatchers.map(&:failure_message_for_should)
        end

        def failing_submatchers
          @failing_submatchers ||= @submatchers.select do |matcher|
            !matcher.matches?(@subject)
          end
        end

        def conditions(conditions)
          @options[:conditions] = conditions
          self
        end

        def class_name(class_name)
          @options[:class_name] = class_name
          self
        end

        def with_foreign_key(foreign_key)
          @options[:foreign_key] = foreign_key
          self
        end

        def validate(validate = true)
          @options[:validate] = validate
          self
        end

        def touch(touch = true)
          @options[:touch] = touch
          self
        end

        def matches?(subject)
          @subject = subject
          association_exists? &&
            macro_correct? &&
            foreign_key_exists? &&
            class_name_correct? &&
            conditions_correct? &&
            join_table_exists? &&
            validate_correct? &&
            touch_correct? &&
            submatchers_match?
        end

        def failure_message_for_should
          "Expected #{expectation} (#{missing})"
        end

        def missing
          [[@missing] + failing_submatchers.map(&:missing_option)].compact.join
        end

        def failure_message_for_should_not
          "Did not expect #{expectation}"
        end

        def description
          description = "#{macro_description} #{@name}"
          description += " class_name => #{@options[:class_name]}" if @options.key?(:class_name)
          [description, @submatchers.map(&:description)].flatten.join(' ')
        end

        protected

        def association_exists?
          if reflection.nil?
            @missing = "no association called #{@name}"
            false
          else
            true
          end
        end

        def macro_correct?
          if reflection.macro == @macro
            true
          else
            @missing = "actual association type was #{reflection.macro}"
            false
          end
        end

        def foreign_key_exists?
          !(belongs_foreign_key_missing? || has_foreign_key_missing?)
        end

        def belongs_foreign_key_missing?
          @macro == :belongs_to && !class_has_foreign_key?(model_class)
        end

        def has_foreign_key_missing?
          [:has_many, :has_one].include?(@macro) &&
            !through? &&
            !class_has_foreign_key?(associated_class)
        end

        def class_name_correct?
          if @options.key?(:class_name)
            if @options[:class_name].to_s == reflection.klass.to_s
              true
            else
              @missing = "#{@name} should resolve to #{@options[:class_name]} for class_name"
              false
            end
          else
            true
          end
        end

        def conditions_correct?
          if @options.key?(:conditions)
            if @options[:conditions].to_s == reflection.options[:conditions].to_s
              true
            else
              @missing = "#{@name} should have the following conditions: #{@options[:conditions]}"
              false
            end
          else
            true
          end
        end

        def join_table_exists?
          if @macro != :has_and_belongs_to_many ||
              model_class.connection.tables.include?(join_table)
            true
          else
            @missing = "join table #{join_table} doesn't exist"
            false
          end
        end

        def validate_correct?
          if option_correct?(:validate)
            true
          else
            @missing = "#{@name} should have :validate => #{@options[:validate]}"
            false
          end
        end

        def touch_correct?
          if option_correct?(:touch)
            true
          else
            @missing = "#{@name} should have :touch => #{@options[:touch]}"
            false
          end
        end

        def option_correct?(key)
          !@options.key?(key) || reflection_set_properly_for?(key)
        end

        def reflection_set_properly_for?(key)
          @options[key] == !!reflection.options[key]
        end

        def class_has_foreign_key?(klass)
          if @options.key?(:foreign_key)
            reflection.options[:foreign_key] == @options[:foreign_key]
          else
            if klass.column_names.include?(foreign_key)
              true
            else
              @missing = "#{klass} does not have a #{foreign_key} foreign key."
              false
            end
          end
        end

        def model_class
          @subject.class
        end

        def join_table
          if reflection.respond_to? :join_table
            reflection.join_table.to_s
          else
            reflection.options[:join_table].to_s
          end
        end

        def associated_class
          reflection.klass
        end

        def foreign_key
          if foreign_key_reflection
            if foreign_key_reflection.respond_to?(:foreign_key)
              foreign_key_reflection.foreign_key.to_s
            else
              foreign_key_reflection.primary_key_name.to_s
            end
          end
        end

        def through?
          reflection.options[:through]
        end

        def reflection
          @reflection ||= model_class.reflect_on_association(@name)
        end

        def foreign_key_reflection
          if [:has_one, :has_many].include?(@macro) && reflection.options.include?(:inverse_of)
            associated_class.reflect_on_association(reflection.options[:inverse_of])
          else
            reflection
          end
        end

        def expectation
          "#{model_class.name} to have a #{@macro} association called #{@name}"
        end

        def macro_description
          case @macro.to_s
          when 'belongs_to'
            'belong to'
          when 'has_many'
            'have many'
          when 'has_one'
            'have one'
          when 'has_and_belongs_to_many'
            'have and belong to many'
          end
        end
      end
    end
  end
end
