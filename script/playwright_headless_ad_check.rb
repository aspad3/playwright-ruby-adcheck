require "playwright"
require "fileutils"

URL = ENV.fetch("TARGET_URL", "https://ameriquestlife.blogspot.com/")
OUTPUT_DIR = "artifacts"
FileUtils.mkdir_p(OUTPUT_DIR)

proxy_server = ENV["PROXY"] # optional: "http://user:pass@host:port"
user_agent = ENV.fetch(
  "USER_AGENT",
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36"
)

def wait_seconds(n)
  puts "⏳ Waiting #{n} second(s)..."
  sleep n
end

Playwright.create(playwright_cli_executable_path: "./node_modules/.bin/playwright") do |playwright|
  launch_options = { headless: true, args: ["--no-sandbox", "--disable-dev-shm-usage"] }
  launch_options[:proxy] = { server: proxy_server } if proxy_server && !proxy_server.empty?

  browser = playwright.chromium.launch(**launch_options)

  context = browser.new_context(
    userAgent: user_agent,
    viewport: { width: 1280, height: 800 },
    javaScriptEnabled: true,
    acceptDownloads: true
  )

  # Anti-detection tweaks
  context.add_init_script(script: <<~JS)
    Object.defineProperty(navigator, 'webdriver', { get: () => false });
    Object.defineProperty(navigator, 'plugins', { get: () => [1,2,3] });
    Object.defineProperty(navigator, 'languages', { get: () => ['en-US', 'en'] });
    const originalQuery = window.navigator.permissions.query;
    window.navigator.permissions.query = (parameters) =>
      parameters.name === 'notifications'
        ? Promise.resolve({ state: Notification.permission })
        : originalQuery(parameters);
  JS


  page = context.new_page
  puts "🌐 Navigating to #{URL} ..."
  response = page.goto(URL, waitUntil: "networkidle")

  if response
    puts "✅ Page loaded with status #{response.status}"
  else
    puts "⚠️ No response received from page"
  end

  wait_seconds 6
  page.evaluate("window.scrollTo(0, document.body.scrollHeight / 2)")
  wait_seconds 4
  page.evaluate("window.scrollTo(0, document.body.scrollHeight)")
  wait_seconds 4

  html = page.content
  File.write(File.join(OUTPUT_DIR, "page.html"), html)
  puts "💾 Saved page HTML to #{OUTPUT_DIR}/page.html"

  screenshot_path = File.join(OUTPUT_DIR, "screenshot.png")
  page.screenshot(path: screenshot_path, fullPage: true)
  puts "📸 Saved screenshot to #{screenshot_path}"

  console_logs = []
  page.on("console", ->(msg) { console_logs << "#{msg.type}: #{msg.text}" })

  wait_seconds 2
  File.write(File.join(OUTPUT_DIR, "console.log"), console_logs.join("\n"))
  puts "📝 Saved console logs to #{OUTPUT_DIR}/console.log"

  browser.close
end

puts "🎉 Done."
