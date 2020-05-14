module SpreeMultiDomain
  class Engine < Rails::Engine
    engine_name 'spree_multi_domain'

    config.autoload_paths += %W(#{config.root}/lib)

    def self.activate
      ['app', 'lib'].each do |dir|
        Dir.glob(File.join(File.dirname(__FILE__), "../../#{dir}/**/*_decorator*.rb")) do |c|
          Rails.application.config.cache_classes ? require(c) : load(c)
        end
      end

      Spree::Config.searcher_class = Spree::Search::MultiDomain
      ApplicationController.send :include, SpreeMultiDomain::MultiDomainHelpers
    end

    config.to_prepare &method(:activate).to_proc

    initializer "templates with dynamic layouts" do |app|
      ActionView::TemplateRenderer.prepend(
        Module.new do
          def render(context, options)
            @view = context
            super(context, options)
          end

          def find_layout(layout, locals, formats=[])
            store_layout = layout
            if @view.respond_to?(:current_store) && @view.current_store && !@view.controller.is_a?(Spree::Admin::BaseController) && !@view.controller.is_a?(Spree::Api::BaseController)
              store_layout = if layout.is_a?(String)
                layout.gsub("layouts/", "layouts/#{@view.current_store.code}/")
              else
                layout.call.try(:gsub, "layouts/", "layouts/#{@view.current_store.code}/")
              end
            end

            begin

              if Rails.gem_version >= Gem::Version.new('5.x') # hack to make it work with rails 4.x and 5.x
                super(store_layout, locals, formats)
              else
                super(store_layout, locals, *formats)
              end

            rescue ::ActionView::MissingTemplate
              if Rails.gem_version >= Gem::Version.new('5.x') # hack to make it work with rails 4.x and 5.x
                super(layout, locals, formats)
              else
                super(layout, locals, *formats)
              end
            end
          end
        end
      )
    end

    initializer "current order decoration" do |app|
      require 'spree/core/controller_helpers/order'
      ::Spree::Core::ControllerHelpers::Order.prepend(
        Module.new do
          def current_order(options = {})
            options[:create_order_if_necessary] ||= false
            super(options)

            if @current_order and current_store and @current_order.store.blank?
              @current_order.update_attribute(:store_id, current_store.id)
            end

            @current_order
          end
        end
      )
    end

    initializer 'spree.promo.register.promotions.rules' do |app|
      app.config.spree.promotions.rules << Spree::Promotion::Rules::Store
    end
  end
end
