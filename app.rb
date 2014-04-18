require './base'
require './fulfillment_service'

if Sinatra::Base.development?
  require 'byebug'
end

class SinatraApp < ShopifyApp

  # Home page
  get '/' do
    erb :home
  end

  # /fulfill
  # reciever of fulfillments/create webhook
  post '/fulfill.json' do
    webhook_session do |shop, params|
      # you can also see the service for individual line items
      # what is the status if there is multiple services?
      # I think I am being lazy here - which may also be why I needed
      # order write permissions to make the find and complete call down below
      return status 200 unless params["service"] == FulfillmentService.name
      order_id = params["order_id"]
      fulfillment_id = params["id"]
      fulfillment = ShopifyAPI::Fulfillment.find(fulfillment_id, :params => {:order_id => order_id})
      fulfillment.complete
      status 200
    end
  end

  # /fetch_stock
  # Listen for a request from Shopify
  # When a request is recieved make a request to fulfillment service
  # Parse response from fulfillment service
  # Respond to Shopify
  #
  # Example of a Shopify request:
  # https://myapp.com/fetch_stock?sku=123&shop=testshop.myshopify.com
  #
  get '/fetch_stock.json' do
    fulfillment_session do |service|
      sku = params["sku"]
      response = service.fetch_stock_levels(sku: sku)
      stock_levels = response.stock_levels

      content_type :json
      stock_levels.to_json
    end
  end

  # /fetch_tracking_numbers
  # Listen for a request from Shopify
  # When a request is recieved make a request to fulfillment service
  # Parse response from fulfillment service
  # Respond to Shopify
  #
  # Example of a Shopify request:
  # http://myapp.com/fetch_tracking_numbers?order_ids[]=1&order_ids[]=2&order_ids[]=3
  #
  get '/fetch_tracking_numbers.json' do
    fulfillment_session do |service|
      order_ids = params["order_ids"]
      response = service.fetch_tracking_numbers(order_ids)
      tracking_numbers = response.tracking_numbers

      content_type :json
      tracking_numbers.to_json
    end
  end

  # form for fulfillment service objects
  get '/fulfillment_service/new' do
    erb :fulfillment_service_new
  end

  post '/fulfillment_service' do
    shopify_session do
      shop_name = session[:shopify][:shop]
      shop = Shop.where(:shop => shop_name).first
      params.merge!(shop: shop)
      service = FulfillmentService.new(params)
      if service.save
        redirect '/'
      else
        redirect '/fulfillment_service/new'
      end
    end
  end

  private

  def install
    shopify_session do
      params = YAML.load(File.read("config/fulfillment_service.yml"))

      fulfillment_service = ShopifyAPI::FulfillmentService.new(params["service"])
      fulfillment_webhook = ShopifyAPI::Webhook.new(params["fulfillment_webhook"])
      uninstall_webhook = ShopifyAPI::Webhook.new(params["uninstall_webhook"])

      # create the fulfillment service if not present
      unless ShopifyAPI::FulfillmentService.find(:all).include?(fulfillment_service)
        fulfillment_service.save
      end

      # create the fulfillment webhook if not present
      unless ShopifyAPI::Webhook.find(:all).include?(fulfillment_webhook)
        fulfillment_webhook.save
      end

      # create the uninstall webhook if not present
      unless ShopifyAPI::Webhook.find(:all).include?(uninstall_webhook)
        uninstall_webhook.save
      end
    end
    redirect '/fulfillment_service/new'
  end

  def uninstall
    webhook_session do |shop, params|
      # remove any dependent models
      service = FulfillmentService.where(shop_id: shop.id).destroy_all
      # remove shop model
      shop.destroy
    end
  end

  def fulfillment_session(&blk)
    shop_name = params["shop"]
    shop = Shop.where(:shop => shop_name).first
    if shop.present?
      service = FulfillmentService.where(shop_id: shop.id).first
      if service.present?
        yield service
      end
    end
  end

end
