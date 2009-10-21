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

    # make your helper avaliable in all views
    # Spree::BaseController.class_eval do
    #   helper YourHelper
    # end
  end
end
