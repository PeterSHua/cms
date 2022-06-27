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
  set :erb, escape_html: true
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
    File.expand_path("test/data", __dir__)
  else
    File.expand_path("data", __dir__)
  end
end

def logged_in?
  session[:logged_in]
end

def prompt_login
  return if logged_in?

  session[:message] = "You must be signed in to do that."
  redirect "/"
end

def accounts
  account_path = if ENV["RACK_ENV"] == "test"
                   File.expand_path("test/accounts.yml", __dir__)
                 else
                   File.expand_path("accounts.yml", __dir__)
                 end

  YAML.load_file(account_path)
end

def valid_password?(user_name, raw_password)
  BCrypt::Password.new(accounts[user_name]) == raw_password
end

# rubocop: disable Metrics/MethodLength
def dup_rgx
  %r{
    \A
    (?<filename>.+)
    (
      \(
      (?<dup_num>\d)
      \)
    ){1}
    \.
    (?<ext>[a-z]+)
    \z
  }ix
end
# rubocop: enable Metrics/MethodLength

def split_filename_rgx
  %r{
    \A
    (?<filename>.+)
    \.
    (?<ext>[a-z]+)
    \z
  }ix
end

# before do; end

# helpers do; end

def search_files
  pattern = File.join(data_path, '*')

  files = Dir.glob(pattern).reject do |path|
    File.directory?(path)
  end

  files.map! do |file|
    File.basename(file)
  end
end

def valid_ext?(ext)
  SUPPORTED_EXT.include?(ext)
end

def invalid_name
  session[:message] = "Invalid file extension. Supported file extensions: "\
                      "#{SUPPORTED_EXT.join(', ')}"
  status 422
end

def new_filename_no_dups(filename)
  name, ext = split_filename_rgx.match(filename).captures

  "#{name}(1).#{ext}"
end

def new_filename_existing_dups(dup_files, name, ext)
  max_dup_file = dup_files.max_by do |file|
    dup_rgx.match(file)[:dup_num]
  end

  max_dup_num = dup_rgx.match(max_dup_file)[:dup_num]

  "#{name}(#{max_dup_num.to_i + 1}).#{ext}"
end

# Split into filename and extension
def split_filename(filename)
  split_filename_rgx.match(filename).captures
end

# Returns an array of filenames with the same name ending with (digit) and same
# extension
def find_dup_files(name, ext)
  search_files.select do |file|
    match_res = dup_rgx.match(file)

    next if match_res.nil?

    dup_name, _dup_num, dup_ext = match_res.captures
    name == dup_name && ext == dup_ext
  end
end

def read_file(filename)
  file_path = File.join(data_path, filename)
  File.read(file_path)
end

# Returns a new filename accounting for existing duplicate filenames
def calc_new_filename(dup_files, filename, name, ext)
  if dup_files.empty?
    new_filename_no_dups(filename)
  else
    new_filename_existing_dups(dup_files, name, ext)
  end
end

def write_file(filename, content)
  file_path = File.join(data_path, filename)
  f = File.new(file_path, "w+")
  f.write(content)
  f.close
end

# Render homepage
get "/" do
  @files = search_files

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
  elsif !valid_ext?(ext)
    invalid_name

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

# Duplicate file
post "/:filename/duplicate" do
  prompt_login

  content = read_file(params[:filename])
  name, ext = split_filename(params[:filename])
  dup_files = find_dup_files(name, ext)

  new_filename = calc_new_filename(dup_files, params[:filename], name, ext)

  write_file(new_filename, content)

  session[:message] = "#{new_filename} was created."

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
post "/:filename/edit" do
  prompt_login

  file_path = File.join(data_path, params[:filename])

  File.write(file_path, params[:content])

  if params[:newfilename]
    ext = params[:newfilename].split('.').last

    if valid_ext?(ext)
      new_file_path = File.join(data_path, params[:newfilename])
      File.rename(file_path, new_file_path)

      flash_msg = "#{params[:newfilename]} has been updated"
    else
      invalid_name
      redirect "/#{params[:filename]}/edit"
    end
  else
    flash_msg = "#{params[:filename]} has been updated."
  end

  session[:message] = flash_msg
  redirect "/"
end
