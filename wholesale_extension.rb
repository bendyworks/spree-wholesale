# Uncomment this if you reference any of your controllers in activate
# require_dependency 'application'

class WholesaleExtension < Spree::Extension
  version "0.1"
  description "Add wholesale pricing to products"
  url "http://github.com/mlambie/spree-wholesale"

  # Please use wholesale/config/routes.rb instead for extension routes.

  # def self.require_gems(config)
  #   config.gem "gemname-goes-here", :version => '1.2.3'
  # end
  
  def activate

    # Add your extension tab to the admin.
    # Requires that you have defined an admin controller:
    # app/controllers/admin/yourextension_controller
    # and that you mapped your admin in config/routes

    #Admin::BaseController.class_eval do
    #  before_filter :add_yourextension_tab
    #
    #  def add_yourextension_tab
    #    # add_extension_admin_tab takes an array containing the same arguments expected
    #    # by the tab helper method:
    #    #   [ :extension_name, { :label => "Your Extension", :route => "/some/non/standard/route" } ]
    #    add_extension_admin_tab [ :yourextension ]
    #  end
    #end
    
    # Reopen the Product class and delegate wholesale_price (first variant)
    Product.class_eval do
      delegate_belongs_to :master, :wholesale_price
    end
    
    # Reopen the ProductsHelper module and redefine the product_price method
    ProductsHelper.class_eval do
      def product_price(product_or_variant, options={})
        options.assert_valid_keys(:format_as_currency, :show_vat_text)
        options.reverse_merge! :format_as_currency => true, :show_vat_text => Spree::Config[:show_price_inc_vat]
        if (!current_user.nil? && current_user.has_role?("wholesale") && !product_or_variant.wholesale_price.blank?)          
          amount = product_or_variant.wholesale_price
        else
          amount = product_or_variant.price
        end
        amount += Calculator::Vat.calculate_tax_on(product_or_variant) if Spree::Config[:show_price_inc_vat]
        options.delete(:format_as_currency) ? format_price(amount, options) : ("%0.2f" % amount).to_f
      end
    end
    
    LineItem.class_eval do
      def wholesale_price
        price
      end
    end
    
    OrdersController.class_eval do
      create.after do    
        params[:products].each do |product_id,variant_id|
          quantity = params[:quantity].to_i if !params[:quantity].is_a?(Array)
          quantity = params[:quantity][variant_id].to_i if params[:quantity].is_a?(Array)
          variant = Variant.find(variant_id)
          if (!current_user.nil? && current_user.has_role?("wholesale") && !variant.wholesale_price.blank?)          
            variant.price = variant.wholesale_price
          end
          @order.add_variant(variant, quantity) if quantity > 0
        end if params[:products]

        params[:variants].each do |variant_id, quantity|
          quantity = quantity.to_i
          variant = Variant.find(variant_id)
          if (!current_user.nil? && current_user.has_role?("wholesale") && !variant.wholesale_price.blank?)          
            variant.price = variant.wholesale_price
          end
          @order.add_variant(variant, quantity) if quantity > 0
        end if params[:variants]

        @order.save

        # store order token in the session
        session[:order_token] = @order.token
      end
    end
    
    Order.class_eval do
      def force_wholesale
        self.line_items.each do |item|
          item.price = Variant.find_by_id(item.variant_id).wholesale_price
        end
        self.save!
      end
      
      def force_retail
        self.line_items.each do |item|
          item.price = Variant.find_by_id(item.variant_id).price
        end
        self.save!
      end
    end
    
    UserSessionsController.class_eval do
      
      before_filter :force_retail_order, :only => [:destroy]
      
      def create
        @user_session = UserSession.new(params[:user_session])
        success = @user_session.save
        respond_to do |format|
          format.html {                                
            if success 
              modify_order_on_login
              flash[:notice] = t("logged_in_succesfully")
              redirect_back_or_default products_path
            else
              flash.now[:error] = t("login_failed")
              render :new
            end
          }
          format.js {
            user = success ? @user_session.record : nil
            render :json => user ? {:ship_address => user.ship_address, :bill_address => user.bill_address}.to_json : success.to_json
          }
        end    
      end
      
      private
      def modify_order_on_login
        user = User.find_by_id(session["user_credentials_id"]) || User.new
        user.has_role?("wholesale") ? force_wholesale_order : force_retail_order
      end
      
      def force_retail_order
        order = Order.find_by_id(session[:order_id])
        order.force_retail if !order.nil? && order.state == 'in_progress'
      end
      
      def force_wholesale_order
        order = Order.find_by_id(session[:order_id])
        order.force_wholesale if !order.nil? && order.state == 'in_progress'
      end
    end

    # make your helper avaliable in all views
    # Spree::BaseController.class_eval do
    #   helper YourHelper
    # end
  end
end
