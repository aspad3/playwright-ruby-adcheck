require 'curb'
require 'json'
require 'fileutils'
require 'dotenv'

# ---------------- Load .env ----------------
Dotenv.load

# ---------------- Configuration ----------------
URL = ENV['TARGET_URL']
OUTPUT_DIR = "artifacts"
FileUtils.mkdir_p(OUTPUT_DIR)

BROWSERLESS_TOKEN = ENV['BROWSERLESS_API_TOKEN']
raise "Please set BROWSERLESS_API_TOKEN" if BROWSERLESS_TOKEN.empty?

USER_AGENT = ENV.fetch(
  "USER_AGENT",
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36"
)

# ---------------- Main ----------------
def send_browserless_request
  # Prepare the query for the mutation
  query = "mutation ClickBody { 
                goto(
                  url: \"#{URL}\", 
                  waitUntil: firstContentfulPaint, 
                  timeout: 60000
                ) { status }
                
                clickBody: click(
                  selector: \"body\",
                  timeout: 60000,
                  visible: true
                ) { selector x y time }
              }"

  # Prepare the payload with the interpolated query
  payload = {
    query: query,
    variables: {},
    operationName: 'ClickBody'
  }

  # Send the POST request using curl
  response = Curl.post("https://production-sfo.browserless.io/chrome/bql?token=#{BROWSERLESS_TOKEN}&proxy=residential&blockConsentModals=true", payload.to_json) do |curl|
    curl.headers = {
      'Content-Type' => 'application/json',
      'User-Agent' => USER_AGENT
    }
    curl.timeout = 300  # Set the timeout for the request (both connection + transfer)
  end

  # Parse and print the response
  response_data = JSON.parse(response.body_str)
  puts "Response: #{response_data}"

  # Save response to file
  save_response_to_file(response_data)
end

# ---------------- Save Outputs ----------------
def save_response_to_file(response_data)
  # Save the response to an output file
  response_path = File.join(OUTPUT_DIR, "response.json")
  File.write(response_path, JSON.pretty_generate(response_data))
  puts "💾 Saved response to #{response_path}"
end

# Run the request
send_browserless_request

puts "🎉 Done."
