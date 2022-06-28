require "tilt/erubis"
require "sinatra"
require "sinatra/reloader"
require "sinatra/content_for"
require "redcarpet"
require "fileutils"
require "yaml"
require "bcrypt"

SUPPORTED_EXT = %w(txt md)
ACCOUNT_FILE = "accounts.yml"
DATA_DIRECTORY = "data"
TEST_DIRECTORY = "test/"

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
    File.expand_path("#{TEST_DIRECTORY}#{DATA_DIRECTORY}", __dir__)
  else
    File.expand_path(DATA_DIRECTORY, __dir__)
  end
end

def account_file_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("#{TEST_DIRECTORY}#{ACCOUNT_FILE}",
                     __dir__)
  else
    File.expand_path(ACCOUNT_FILE, __dir__)
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
  YAML.load_file(account_file_path)
end

def valid_password?(password)
  (4..10).cover?(password.size) && !/\s/.match?(password)
end

def correct_password?(username, raw_password)
  return false if accounts[username].nil?

  BCrypt::Password.new(accounts[username]) == raw_password
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
  match_res = split_filename_rgx.match(filename)

  return nil if match_res.nil?

  match_res.captures
end

# Returns an array of filenames with the same name ending with "($DIGIT)"
# and the same extension
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
  File.write(file_path, content)
end

def valid_username?(username)
  (4..10).cover?(username.size) && !/[^\w]/.match?(username)
end

def acc_exists?(username)
  accounts.keys.include?(username)
end

def validate_password(password)
  (4..10).cover?(password.size) && !/\s/.match?(password)
end

def register_acc(username, password)
  accounts_new = accounts
  accounts_new[username] = BCrypt::Password.create(password).to_s

  File.write(account_file_path, YAML.dump(accounts_new))
end

# before do; end

# helpers do; end

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

# Write to file
post "/:filename/edit" do
  prompt_login

  file_path = File.join(data_path, params[:filename])
  File.write(file_path, params[:content])

  if params[:newfilename]
    ext = split_filename(params[:newfilename])

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

# Render login page
get "/login" do
  erb :login, layout: :layout
end

# Login
post "/login" do
  # Validate username

  if valid_password?(params[:password]) &&
     correct_password?(params[:username], params[:password])
    session[:username] = params[:username]
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
  session[:username] = nil

  session[:message] = "You have been signed out."

  redirect "/"
end

# Signup
get "/register" do
  if session[:logged_in]
    session[:message] = "You're already logged in."

    redirect "/"
  else
    erb :register, layout: :layout
  end
end

# Create account
# rubocop: disable Metrics/BlockLength
post "/register" do
  if session[:logged_in]
    session[:message] = "You're already logged in."

    redirect "/"
  elsif acc_exists?(params[:username])
    session[:message] = "That account name already exists."
    status 422

    erb :register, layout: :layout
  elsif !valid_username?(params[:username])
    session[:message] = "Username must consist of only letters and numbers, "\
                        "and must be between 4-10 characters."
    status 422

    erb :register, layout: :layout
  elsif !valid_password?(params[:password])
    session[:message] = "Password must be between 4-10 characters and cannot "\
                        "contain spaces."
    status 422

    erb :register, layout: :layout
  else
    register_acc(params[:username], params[:password])

    session[:message] = "Your account has been registered."
    session[:logged_in] = true
    session[:username] = params[:username]

    redirect "/"
  end
end
# rubocop: enable Metrics/BlockLength
