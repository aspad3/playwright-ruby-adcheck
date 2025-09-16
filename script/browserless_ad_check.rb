class BrowserlessAdCheck
  OUTPUT_DIR = "artifacts"

  def initialize
    # Load environment variables directly from ENV (no need for Dotenv)
    @domain_url = ENV['DOMAIN_URL']
    @target_url = ENV['TARGET_URL']
    @browserless_token = ENV['BROWSERLESS_API_TOKEN']
    @user_agent = ENV.fetch(
      "USER_AGENT",
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36"
    )

    # Validate environment variables
    raise "Please set BROWSERLESS_API_TOKEN in the environment" if @browserless_token.to_s.strip.empty?
    raise "Please set DOMAIN_URL in the environment" if @domain_url.to_s.strip.empty?

    # Create the output directory if it doesn't exist
    FileUtils.mkdir_p(OUTPUT_DIR)
  end

  def run
    url = @target_url.nil? ? fetch_sitemap_url : @target_url
    puts "INSPECT URL #{url.inspect}"
    url = url.nil? ? ENV['DOMAIN_URL'] : url

    if url.nil? || url.strip.empty?
      puts "❌ URL is empty, skipping..."
      return
    end

    send_browserless_request(url)
    puts "🎉 Done."
  end

  private

  def fetch_sitemap_url
    domain = URI(@domain_url).scheme + "://" + URI(@domain_url).host
    sitemap_url = "#{domain}/sitemap.xml"

    puts "📥 Fetching sitemap: #{sitemap_url}"
    response = Curl.get(sitemap_url) do |curl|
      curl.headers['User-Agent'] = @user_agent
      curl.timeout = 60
      curl.follow_location = true
    end

    doc = Nokogiri::XML(response.body_str)
    doc.remove_namespaces!

    urls = []

    # If sitemap is an index, fetch sub-sitemaps
    sitemap_nodes = doc.xpath('//sitemap/loc').map(&:text)
    if sitemap_nodes.any?
      puts "📑 Found sitemap index with #{sitemap_nodes.size} sub-sitemaps"
      picked_sitemap = sitemap_nodes.sample
      puts "👉 Fetching sub-sitemap: #{picked_sitemap}"

      sub_response = Curl.get(picked_sitemap) do |curl|
        curl.headers['User-Agent'] = @user_agent
        curl.timeout = 60
        curl.follow_location = true
      end

      sub_doc = Nokogiri::XML(sub_response.body_str)
      sub_doc.remove_namespaces!
      urls = sub_doc.xpath('//url/loc').map(&:text)
    else
      # If it's a direct URL set
      urls = doc.xpath('//url/loc').map(&:text)
    end

    # Fallback for Blogger URLs
    if urls.empty?
      fallback = "#{domain}/sitemap.xml?orderby=UPDATED"
      puts "⚠️ Sitemap empty, trying fallback: #{fallback}"
      res = Curl.get(fallback) do |c|
        c.headers['User-Agent'] = @user_agent
        c.timeout = 60
        c.follow_location = true
      end
      fb_doc = Nokogiri::XML(res.body_str)
      fb_doc.remove_namespaces!
      urls = fb_doc.xpath('//url/loc').map(&:text)
    end

    raise "❌ No URLs found in sitemap (even after fallback)" if urls.empty?

    picked_url = urls.sample
    puts "✅ Picked random URL from sitemap: #{picked_url}"
    picked_url
  end

  def send_browserless_request(url)
    puts "🌍 Visiting URL: #{url}"

    query = "mutation ClickBody { 
                  goto(
                    url: \"#{url}\", 
                    waitUntil: firstContentfulPaint, 
                    timeout: 60000
                  ) { status }
                  
                  clickBody: click(
                    selector: \"body\",
                    timeout: 60000,
                    visible: true
                  ) { selector x y time }
                }"

    payload = {
      query: query,
      variables: {},
      operationName: 'ClickBody'
    }

    response = Curl.post("https://production-sfo.browserless.io/chrome/bql?token=#{@browserless_token}&proxy=residential&blockConsentModals=true", payload.to_json) do |curl|
      curl.headers = {
        'Content-Type' => 'application/json',
        'User-Agent' => @user_agent
      }
      curl.timeout = 300
    end

    response_data = JSON.parse(response.body_str)
    puts "📡 Response: #{response_data}"

    save_response_to_file(response_data, url)
  end

  def save_response_to_file(response_data, url)
    timestamp = Time.now.strftime("%Y%m%d_%H%M%S")
    response_path = File.join(OUTPUT_DIR, "response_#{timestamp}.json")

    File.write(response_path, JSON.pretty_generate({
      visited_url: url,
      response: response_data
    }))

    puts "💾 Saved response + visited URL to #{response_path}"
  end
end

# ---------------- Run ----------------
if __FILE__ == $0
  BrowserlessAdCheck.new.run
end
