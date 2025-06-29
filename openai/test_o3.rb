#!/usr/bin/env ruby

require 'net/http'
require 'json'
require 'uri'

API_KEY = ENV['OPENAI_API_KEY']
unless API_KEY
  puts "環境変数 OPENAI_API_KEY を設定してください"
  exit 1
end

def call_openai_o3(prompt)
  uri = URI('https://api.openai.com/v1/chat/completions')

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true

  request = Net::HTTP::Post.new(uri)
  request['Authorization'] = "Bearer #{API_KEY}"
  request['Content-Type'] = 'application/json'

  request.body = {
    model: 'o3',
    messages: [
      {
        role: 'user',
        content: prompt
      }
    ],
    max_completion_tokens: 1000
  }.to_json

  response = http.request(request)

  if response.code == '200'
    result = JSON.parse(response.body)
    puts "レスポンス:"
    puts result['choices'][0]['message']['content']
  else
    puts "エラー: #{response.code}"
    puts response.body
  end
end

if ARGV.empty?
  prompt = "Hello! Can you tell me what you are?"
else
  prompt = ARGV.join(' ')
end

puts "プロンプト: #{prompt}"
puts "OpenAI o3 に送信中..."

call_openai_o3(prompt)
