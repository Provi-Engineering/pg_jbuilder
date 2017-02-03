require 'pg_jbuilder/version'
require 'pg_jbuilder/railtie' if defined?(Rails)

module PgJbuilder
  @paths = [
    File.join(File.dirname(__FILE__),'..','queries')
  ]
  class TemplateNotFound < ::Exception; end
  @cache = {}
  
  class BuilderDSL
    def initialize(variables={})
      @variables = variables
    end
    
    def method_missing(name)
      @variables[name]
    end
    
    def object(query=nil, variables={}, &block)
      if block_given?
        _erbout = block.binding.eval('_erbout')
        _erbout << "(SELECT COALESCE(row_to_json(object_row),'{}'::json) FROM ("
        block.call
        _erbout << ")object_row)"
      else
        content = include(query, variables)
      end
      
      # "(SELECT COALESCE(row_to_json(object_row),'{}'::json) FROM (" +
      #   content +
      #   ")object_row)"
    end
    
    def array(query=nil, variables={}, &block)
      if block_given?
        content = yield
      else
        content = include(query, variables)
      end
      
      "(SELECT COALESCE(array_to_json(array_agg(row_to_json(array_row))),'[]'::json) FROM (" +
        content +
        ")array_row)"
    end
    
    def quote(value)
      PgJbuilder.connection.quote(value)
    end
    
    def include(query, variables={})
      dsl = new_sub_dsl(variables)
      PgJbuilder.render(query, variables, dsl: dsl)
      # render_helper context, value, options
      #
      # def self.render_helper context, value, options
      #   variables = Hash[context.collect{|k,v|[k,v]}]
      #   options['hash'].each{|k,v| variables[k] = v} if options
      #   PgJbuilder.render value, variables
      # end
    end
    
    def get_binding
      binding
    end
    
    def new_sub_dsl(variables)
      self.class.new(@variables.merge(variables))
    end
  end

  def self.render_object *args
    result = render(*args)
    "SELECT COALESCE(row_to_json(object_row),'{}'::json)\nFROM (\n#{result}\n) object_row"
  end

  def self.render_array *args
    result = render(*args)
    "SELECT COALESCE(array_to_json(array_agg(row_to_json(array_row))),'[]'::json)\nFROM (\n#{result}\n) array_row"
  end


  def self.render query, variables={}, options={}
    compiled = @cache[query] || ERB.new(get_query_contents(query))
    @cache[query] ||= compiled
    dsl = options[:dsl] || BuilderDSL.new(variables)
    compiled.result(dsl.get_binding)
  end

  def self.paths
    @paths
  end

  def self.connection= value
    @connection = value
  end
  
  def self.clear_cache
    @cache = {}
  end

  def self.connection
    if @connection.is_a?(Proc)
      @connection.call
    else
      @connection
    end
  end

  private

  def self.get_query_contents query
    File.read path_name(query)
  end

  def self.path_name *args
    last_arg = args.pop
    query_name = last_arg
    last_arg += '.sql'
    args.push last_arg
    @paths.each do |path|
      file = File.join(path,*args)
      if File.exists?(file) && File.file?(file)
        return file
      end
    end
    raise TemplateNotFound.new("Template #{query_name} was not found in any source paths")
  end
end