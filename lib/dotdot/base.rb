module Dotdot
  class Base
    attr_reader :database

    def initialize(object)
      @object = object
      @database = nil
      @sql_options = { :logger => @object.logger, :sql_log_level => :info }

      if @object.options[:verbose]
        @sql_options[:sql_log_level] = :debug
      end
    end

    def boot
      @database = Sequel.sqlite(@object.db_path, @sql_options)
      @group = ""
      @prefix_stack = []

      @dataset = @database[:cablingdatas]
    end

    def final_key(key)
      unless @prefix_stack.empty?
        @prefix_stack.push(key)
        key = nil
      end

      key ||= @prefix_stack.join('.')
    end

    def set(key, value, group = nil)
      group ||= @group
      key = final_key(key)

      @dataset.insert(:key => key, :value => value, :group => group)

      stack_pop
    end

    def delete_key(key, group = nil)
      group ||= @group

      key = final_key(key)

      @dataset.filter(:key => key, :group => group).delete
      stack_pop
    end

    def update(key, value, group = nil)
      group ||= @group
      key = final_key(key)

      @dataset.filter(:key => key, :group => group).update(:value => value)

      stack_pop
    end

    def group(group = nil, &block)
      @group = group

      @database.transaction do
        yield
      end
    end

    def globals(&block)
      @group = "globals"

      @database.transaction do
        yield
      end
    end

    def prefix(prefix, &block)
      @prefix_stack.push(prefix)
      yield

      stack_pop
    end

    def stack_pop
      @prefix_stack.pop
    end

    def has_key?(key, group)
      group ||= @object.group.to_s

      val = @dataset.where(:key => key, :group => group).count

      if val == 0
        val = @dataset.where(:key => key, :group => "globals").count

        val == 0 ? false : true
      else
        true
      end
    end

    def get(key, group = nil)
      group ||= @object.group.to_s

      val = @dataset.where(:key => key, :group => group)

      if val.empty?
        val = @dataset.where(:key => key, :group => "globals")
      end

      if val.count > 0
        val.first[:value]
      else
        raise "key \'#{key}\' cannot be found!"
      end
    end

    def get_if_key_exists(key, group = nil)
      group ||= @object.group.to_s

      get(key, group) if has_key?(key, group)
    end

    def get_children(key, group = nil)
      group ||= @object.group.to_s
      values = []

      res = @dataset.where(:key.like("#{key}%"), :group => group)

      if res.empty?
        res = @dataset.where(:key.like("#{key}%"), :group => "globals")
      end

      key = key.split('.')

      res.each do |r|
        res_key = r[:key].split('.')
        res_key = (res_key - key).shift
        values.push(res_key)
      end

      if values.count > 0
        values & values
      else
        raise "no values for \'#{key}\'!"
      end
    end

    def create_table_if_needed
      if @database.tables.include? :cablingdatas
        @database.drop_table :cablingdatas
      end

      @database.create_table :cablingdatas do
        String :key
        String :value
        String :group
      end
    end
  end
end
