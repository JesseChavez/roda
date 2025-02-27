# frozen-string-literal: true

require "tilt"

class Roda
  module RodaPlugins
    # The render plugin adds support for template rendering using the tilt
    # library.  Two methods are provided for template rendering, +view+
    # (which uses the layout) and +render+ (which does not).
    #
    #   plugin :render
    #
    #   route do |r|
    #     r.is 'foo' do
    #       view('foo') # renders views/foo.erb inside views/layout.erb
    #     end
    #
    #     r.is 'bar' do
    #       render('bar') # renders views/bar.erb
    #     end
    #   end
    #
    # You can provide options to the plugin method:
    #
    #   plugin :render, :engine=>'haml', :views=>'admin_views'
    #
    # = Plugin Options
    #
    # The following plugin options are supported:
    #
    # :cache :: nil/false to not cache templates (useful for development), defaults
    #           to true unless RACK_ENV is development to automatically use the
    #           default template cache.
    # :cache_class :: A class to use as the template cache instead of the default.
    # :engine :: The tilt engine to use for rendering, also the default file extension for
    #            templates, defaults to 'erb'.
    # :escape :: Use Roda's Erubis escaping support, which makes <tt><%= %></tt> escape output,
    #            <tt><%== %></tt> not escape output, and handles postfix conditions inside
    #            <tt><%= %></tt> tags.
    # :escape_safe_classes :: String subclasses that should not be HTML escaped when used in
    #                         <tt><%= %></tt> tags, when :escape is used. Can be an array for multiple classes.
    # :escaper :: Object used for escaping output of <tt><%= %></tt>, when :escape is used,
    #             overriding the default.  If given, object should respond to +escape_xml+ with
    #             a single argument and return an output string.
    # :layout :: The base name of the layout file, defaults to 'layout'.
    # :layout_opts :: The options to use when rendering the layout, if different
    #                 from the default options.
    # :template_opts :: The tilt options used when rendering all templates. defaults to:
    #                   <tt>{:outvar=>'@_out_buf', :default_encoding=>Encoding.default_external}</tt>.
    # :engine_opts :: The tilt options to use per template engine.  Keys are
    #                 engine strings, values are hashes of template options.
    # :views :: The directory holding the view files, defaults to the 'views' subdirectory of the
    #           application's :root option (the process's working directory by default).
    #
    # = Render/View Method Options
    #
    # Most of these options can be overridden at runtime by passing options
    # to the +view+ or +render+ methods:
    #
    #   view('foo', :engine=>'html.erb')
    #   render('foo', :views=>'admin_views')
    #
    # There are additional options to +view+ and +render+ that are
    # available at runtime:
    #
    # :cache :: Set to false to not cache this template, even when
    #           caching is on by default.  Set to true to force caching for
    #           this template, even when the default is to not cache (e.g.
    #           when using the :template_block option).
    # :cache_key :: Explicitly set the hash key to use when caching.
    # :content :: Only respected by +view+, provides the content to render
    #             inside the layout, instead of rendering a template to get
    #             the content.
    # :inline :: Use the value given as the template code, instead of looking
    #            for template code in a file.
    # :locals :: Hash of local variables to make available inside the template.
    # :path :: Use the value given as the full pathname for the file, instead
    #          of using the :views and :engine option in combination with the
    #          template name.
    # :scope :: The object in which context to evaluate the template.  By
    #           default, this is the Roda instance.
    # :template :: Provides the name of the template to use.  This allows you
    #              pass a single options hash to the render/view method, while
    #              still allowing you to specify the template name.
    # :template_block :: Pass this block when creating the underlying template,
    #                    ignored when using :inline.  Disables caching of the
    #                    template by default.
    # :template_class :: Provides the template class to use, inside of using
    #                    Tilt or <tt>Tilt[:engine]</tt>.
    #
    # Here's how those options are used:
    #
    #   view(:inline=>'<%= @foo %>')
    #   render(:path=>'/path/to/template.erb')
    #
    # If you pass a hash as the first argument to +view+ or +render+, it should
    # have either +:template+, +:inline+, +:path+, or +:content+ (for +view+) as
    # one of the keys.
    #
    # = Speeding Up Template Rendering
    #
    # By default, determining the cache key to use for the template can be a lot
    # of work.  If you specify the +:cache_key+ option, you can save Roda from
    # having to do that work, which will make your application faster.  However,
    # if you do this, you need to make sure you choose a correct key.
    #
    # If your application uses a unique template per path, in that the same
    # path never uses more than one template, you can use the +view_options+ plugin
    # and do:
    #
    #   set_view_options :cache_key=>r.path_info
    #
    # at the top of your route block.  You can even do this if you do have paths
    # that use more than one template, as long as you specify +:cache_key+
    # specifically when rendering in those paths.
    #
    # If you use a single layout in your application, you can also make layout
    # rendering faster by specifying +:cache_key+ inside the +:layout_opts+
    # plugin option.
    module Render
      OPTS={}.freeze

      def self.load_dependencies(app, opts=OPTS)
        if opts[:escape]
          app.plugin :_erubis_escaping
        end
      end

      # Setup default rendering options.  See Render for details.
      def self.configure(app, opts=OPTS)
        if app.opts[:render]
          opts = app.opts[:render][:orig_opts].merge(opts)
        end
        app.opts[:render] = opts.dup
        app.opts[:render][:orig_opts] = opts

        opts = app.opts[:render]
        opts[:engine] = (opts[:engine] || opts[:ext] || "erb").dup.freeze
        opts[:views] = File.expand_path(opts[:views]||"views", app.opts[:root]).freeze

        if opts.fetch(:cache, ENV['RACK_ENV'] != 'development')
          if cache_class = opts[:cache_class]
            opts[:cache] = cache_class.new
          else
            opts[:cache] = app.thread_safe_cache
          end
        end

        opts[:layout_opts] = (opts[:layout_opts] || {}).dup
        opts[:layout_opts][:_is_layout] = true
        if layout = opts.fetch(:layout, true)
          opts[:layout] = true unless opts.has_key?(:layout)

          case layout
          when Hash
            opts[:layout_opts].merge!(layout)
          when true
            opts[:layout_opts][:template] ||= 'layout'
          else
            opts[:layout_opts][:template] = layout
          end
        end
        opts[:layout_opts].freeze

        template_opts = opts[:template_opts] = (opts[:template_opts] || {}).dup
        template_opts[:outvar] ||= '@_out_buf'
        if RUBY_VERSION >= "1.9" && !template_opts.has_key?(:default_encoding)
          template_opts[:default_encoding] = Encoding.default_external
        end
        if opts[:escape]
          template_opts[:engine_class] = ErubisEscaping::Eruby

          opts[:escaper] ||= if opts[:escape_safe_classes]
            ErubisEscaping::UnsafeClassEscaper.new(opts[:escape_safe_classes])
          else
            ::Erubis::XmlHelper
          end
        end
        template_opts.freeze

        engine_opts = opts[:engine_opts] = (opts[:engine_opts] || {}).dup
        engine_opts.to_a.each do |k,v|
          engine_opts[k] = v.dup.freeze
        end
        engine_opts.freeze

        opts.freeze
      end

      module ClassMethods
        # Copy the rendering options into the subclass, duping
        # them as necessary to prevent changes in the subclass
        # affecting the parent class.
        def inherited(subclass)
          super
          opts = subclass.opts[:render] = subclass.opts[:render].dup

          if opts[:cache]
            if cache_class = opts[:cache_class]
              opts[:cache] = cache_class.new
            else
              opts[:cache] = thread_safe_cache
            end
          end

          opts.freeze
        end

        # Return the render options for this class.
        def render_opts
          opts[:render]
        end
      end

      module InstanceMethods
        # Render the given template. See Render for details.
        def render(template, opts = OPTS, &block)
          opts = parse_template_opts(template, opts)
          merge_render_locals(opts)
          retrieve_template(opts).render((opts[:scope]||self), (opts[:locals]||OPTS), &block)
        end

        # Return the render options for the instance's class. While this
        # is not currently frozen, it may be frozen in a future version,
        # so you should not attempt to modify it.
        def render_opts
          self.class.render_opts
        end

        # Render the given template.  If there is a default layout
        # for the class, take the result of the template rendering
        # and render it inside the layout.  See Render for details.
        def view(template, opts=OPTS)
          opts = parse_template_opts(template, opts)
          content = opts[:content] || render_template(opts)

          if layout_opts  = view_layout_opts(opts)
            content = render_template(layout_opts){content}
          end

          content
        end

        private

        # Private alias for render.  Should be used by other plugins when they want to render a template
        # without a layout, as plugins can override render to use a layout.
        alias render_template render

        # If caching templates, attempt to retrieve the template from the cache.  Otherwise, just yield
        # to get the template.
        def cached_template(opts, &block)
          if (cache = render_opts[:cache]) && (key = opts[:cache_key])
            unless template = cache[key]
              template = cache[key] = yield
            end
            template
          else
            yield
          end
        end

        # Given the template name and options, set the template class, template path/content,
        # template block, and locals to use for the render in the passed options.
        def find_template(opts)
          render_opts = render_opts()
          engine_override = opts[:engine] ||= opts[:ext]
          engine = opts[:engine] ||= render_opts[:engine]
          if content = opts[:inline]
            path = opts[:path] = content
            template_class = opts[:template_class] ||= ::Tilt[engine]
            opts[:template_block] = Proc.new{content}
          else
            opts[:views] ||= render_opts[:views]
            path = opts[:path] ||= template_path(opts)
            template_class = opts[:template_class]
            opts[:template_class] ||= ::Tilt
          end

          if render_opts[:cache]
            if (cache = opts[:cache]).nil?
              cache = content || !opts[:template_block]
            end

            if cache
              template_block = opts[:template_block] unless content
              template_opts = opts[:template_opts]

              opts[:cache_key] ||= if template_class || engine_override || template_opts || template_block
                [path, template_class, engine_override, template_opts, template_block]
              else
                path
              end
            else
              opts.delete(:cache_key)
            end
          end

          opts
        end

        # Merge any :locals specified in the render_opts into the :locals option given.
        def merge_render_locals(opts)
          if !opts[:_is_layout] && (r_locals = render_opts[:locals])
            opts[:locals] = if locals = opts[:locals]
              Hash[r_locals].merge!(locals)
            else
              r_locals
            end
          end
        end

        # Return a single hash combining the template and opts arguments.
        def parse_template_opts(template, opts)
          opts = Hash[opts]
          if template.is_a?(Hash)
            opts.merge!(template)
          else
            opts[:template] = template
            opts
          end
        end

        # The default render options to use.  These set defaults that can be overridden by
        # providing a :layout_opts option to the view/render method.
        def render_layout_opts
          Hash[render_opts[:layout_opts]]
        end

        # Retrieve the Tilt::Template object for the given template and opts.
        def retrieve_template(opts)
          unless opts[:cache_key] && opts[:cache] != false
            found_template_opts = opts = find_template(opts)
          end
          cached_template(opts) do
            opts = found_template_opts || find_template(opts)
            template_opts = render_opts[:template_opts]
            if engine_opts = render_opts[:engine_opts][opts[:engine]]
              template_opts = Hash[template_opts].merge!(engine_opts)
            end
            if current_template_opts = opts[:template_opts]
              template_opts = Hash[template_opts].merge!(current_template_opts)
            end
            opts[:template_class].new(opts[:path], 1, template_opts, &opts[:template_block])
          end
        end

        # The name to use for the template.  By default, just converts the :template option to a string.
        def template_name(opts)
          opts[:template].to_s
        end

        # The template path for the given options.
        def template_path(opts)
          "#{opts[:views]}/#{template_name(opts)}.#{opts[:engine]}"
        end

        # If a layout should be used, return a hash of options for
        # rendering the layout template.  If a layout should not be
        # used, return nil.
        def view_layout_opts(opts)
          if layout = opts.fetch(:layout, render_opts[:layout])
            layout_opts = render_layout_opts
            if l_opts = opts[:layout_opts]
              if (l_locals = l_opts[:locals]) && (layout_locals = layout_opts[:locals])
                set_locals = Hash[layout_locals].merge!(l_locals)
              end
              layout_opts.merge!(l_opts)
              if set_locals
                layout_opts[:locals] = set_locals
              end
            end

            case layout
            when Hash
              layout_opts.merge!(layout)
            when true
              # use default layout
            else
              layout_opts[:template] = layout
            end

            layout_opts
          end
        end
      end
    end

    register_plugin(:render, Render)
  end
end
