# Convertible provides methods for converting a pagelike item
# from a certain type of markup into actual content
#
# Requires
#   self.site -> Jekyll::Site
module Jekyll
  module Convertible
    # Return the contents as a string
    def to_s
      self.content || ''
    end

    # Read the YAML frontmatter
    #   +base+ is the String path to the dir containing the file
    #   +name+ is the String filename of the file
    #
    # Returns nothing
    def read_yaml(base, name)
      self.content = File.read(File.join(base, name))

      if self.content =~ /^(---\s*\n.*?)\n---\s*\n/m
        self.content = self.content[($1.size + 5)..-1]

        self.data ||= {}
        self.data = self.data.merge(YAML.load($1))
      end
    end

    # Transform the contents based on the file extension.
    #
    # Returns nothing
    def transform
      case self.content_type
      when 'textile'
        self.ext = ".html"
        self.content = self.site.textile(self.content)
      when 'markdown'
        self.ext = ".html"
        self.content = self.site.markdown(self.content)
      when 'haml'
        self.ext = ".html"
        haml_options = { 
          :attr_wrapper => %{"},
          :filename => @name
        }

        more_options = {}
        more_options.merge!(self.site.config['haml_options']) if self.site.config.has_key? 'haml_options'
        more_options.merge!(self.data['haml_options']) if self.data.has_key? 'haml_options'

        more_options.each do |key, val|
          # convert string values starting with ':' to symbols
          val = val[1..val.length].to_sym if val.class == String and val[0..0] == ':'
          haml_options[key.to_sym] = val
        end

        # Actually rendered in do_layout.
        self.content = Haml::Engine.new(self.content, haml_options)
      end
    end

    # Determine which formatting engine to use based on this convertible's
    # extension
    #
    # Returns one of :textile, :markdown or :unknown
    def content_type
      case self.ext[1..-1]
      when /textile/i
        return 'textile'
      when /markdown/i, /mkdn/i, /md/i
        return 'markdown'
      when /haml/i
        return 'haml'
      end
      return 'unknown'
    end
    
    # Sets up a context for Haml and renders in it. The context has accessors
    # matching the passed-in hash, e.g. "site", "page" and "content", and has
    # helper modules mixed in.
    #
    # Returns String.
    def render_haml_in_context(haml_engine, params={})
      context = ClosedStruct.new(params)
      context.extend(HamlHelpers)
      context.extend(::Helpers) if defined?(::Helpers)
      haml_engine.render(context)
    end

    # Add any necessary layouts to this convertible document
    #   +layouts+ is a Hash of {"name" => "layout"}
    #   +site_payload+ is the site payload hash
    #
    # Returns nothing
    def do_layout(payload, layouts)
      info = { :filters => [Jekyll::Filters], :registers => { :site => self.site } }

      # render and transform content (this becomes the final content of the object)
      payload["content_type"] = self.content_type
      
      if self.content_type == "haml"
        self.transform
        self.content = render_haml_in_context(self.content,
          :site => self.site,
          :page => ClosedStruct.new(payload["page"]))
      else
        self.content = Liquid::Template.parse(self.content).render(payload, info)
        self.transform
      end

      # output keeps track of what will finally be written
      self.output = self.content

      # recursively render layouts
      layout = layouts[self.data["layout"]]
      while layout
        payload = payload.deep_merge({"content" => self.output, "page" => layout.data})
        
        if site.config['haml'] && layout.content.is_a?(Haml::Engine)
          self.output = render_haml_in_context(layout.content, 
            :site => ClosedStruct.new(payload["site"]),
            :page => ClosedStruct.new(payload["page"]),
            :content => payload["content"])
        else
          self.output = Liquid::Template.parse(layout.content).render(payload, info)
        end

        layout = layouts[layout.data["layout"]]
      end
    end
  end
end
