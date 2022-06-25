require "tilt/erubis"
require "sinatra"
require "sinatra/reloader"
require "sinatra/content_for"
require "redcarpet"
require "fileutils"
require "yaml"
require "bcrypt"

SUPPORTED_EXT = %w(txt md)

configure do
  enable :sessions
  set :session_secret, 'super secret'
  set :erb, :escape_html => true
end

def render_markdown(text)
  markdown = Redcarpet::Markdown.new(Redcarpet::Render::HTML)
  markdown.render(text)
end

def load_file_content(path)
  content = File.read(path)
  case File.extname(path)
  when ".txt"
    headers["Content-Type"] = "text/plain"
    content
  when ".md"
    erb render_markdown(content)
  end
end

def data_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/data", __FILE__)
  else
    File.expand_path("../data", __FILE__)
  end
end

def logged_in?
  session[:logged_in]
end

def prompt_login
  unless logged_in?
    session[:message] = "You must be signed in to do that."
    redirect "/"
  end
end

def accounts
  account_path = if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/accounts.yml", __FILE__)
  else
    File.expand_path("../accounts.yml", __FILE__)
  end

  YAML.load_file(account_path)
end

def valid_password?(user_name, raw_password)
  BCrypt::Password.new(accounts[user_name]) == raw_password
end

before do

end

helpers do

end

# Render homepage
get "/" do
  pattern = File.join(data_path, '*')

  @files = Dir.glob(pattern).reject do |path|
    File.directory?(path)
  end

  @files.map! do |file|
    File.basename(file)
  end

  erb :home
end

# Display file
get "/:filename/view" do
  file_path = File.join(data_path, params[:filename])

  if File.file?(file_path)
    load_file_content(file_path)
  else
    session[:message] = "#{params[:filename]} does not exist."
    redirect "/"
  end
end

# Render edit page
get "/:filename/edit" do
  prompt_login

  file_path = File.join(data_path, params[:filename])

  @filename = params[:filename]
  @content = File.read(file_path)

  erb :edit, layout: :layout
end

# Create a file
post "/new" do
  prompt_login

  file_name = params[:filename]

  ext = file_name.split('.').last

  if file_name.empty?
    session[:message] = "A name is required."
    status 422
    erb :new, layout: :layout
  elsif !SUPPORTED_EXT.include?(ext)
    session[:message] = "Invalid file extension. Supported file extensions: #{SUPPORTED_EXT.join(', ')}"
    status 422
    erb :new, layout: :layout
  else
    file_path = File.join(data_path, file_name)
    File.new(file_path, "w+")

    session[:message] = "#{file_name} was created."

    redirect "/"
  end
end

# Render file creation page
get "/new" do
  prompt_login

  erb :new, layout: :layout
end

# Delete a file
post "/:filename/delete" do
  prompt_login

  file_path = File.join(data_path, params[:filename])
  FileUtils.rm_rf(file_path)

  session[:message] = "#{params[:filename]} was deleted."

  redirect "/"
end

# Login page
get "/login" do
  erb :login, layout: :layout
end

# Login
post "/login" do
  if valid_password?(params[:user_name], params[:password])
    session[:user_name] = params[:user_name]
    session[:message] = "Welcome!"
    session[:logged_in] = true
    redirect "/"
  else
    session[:message] = "Invalid Credentials!"
    status 422
    erb :login
  end
end

# Logout
post "/logout" do
  session[:logged_in] = false
  session[:user_name] = nil

  session[:message] = "You have been signed out."

  redirect "/"
end

# Write to file
post "/:filename" do
  prompt_login

  file_path = File.join(data_path, params[:filename])

  f = File.open(file_path, 'w')
  f.write(params[:content])
  f.close

  session[:message] = "#{params[:filename]} has been updated."

  redirect "/"
end
