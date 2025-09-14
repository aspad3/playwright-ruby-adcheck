$stdout.sync = true
require "playwright"

Playwright.create(
  playwright_cli_executable_path: "./node_modules/.bin/playwright"
) do |playwright|
  browser = playwright.chromium.launch(headless: true)
  page = browser.new_page
  puts "🌐 Opening..."
  response = page.goto("https://example.com", waitUntil: "domcontentloaded", timeout: 10_000)
  puts "✅ Status: #{response&.status}"
  puts "✅ Title: #{page.title}"
  browser.close
end
