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
DOC_DIR = "public/docs"
IMG_DIR = "public/images"
TEST_DIR = "test"
VERSIONS_DIR ="versions"

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
    File.expand_path(File.join(TEST_DIR, DOC_DIR), __dir__)
  else
    File.expand_path(DOC_DIR, __dir__)
  end
end

def img_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path(File.join(TEST_DIR, IMG_DIR), __dir__)
  else
    File.expand_path(IMG_DIR, __dir__)
  end
end

def account_file_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path(File.join(TEST_DIR, ACCOUNT_FILE), __dir__)
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

def search_files(path)
  pattern = File.join(path, '*')

  files = Dir.glob(pattern).reject do |file_path|
    File.directory?(file_path)
  end

  files.map! do |file|
    File.basename(file)
  end
end

def valid_ext?(filename_arr)
  return false unless filename_arr.is_a?(Array) && filename_arr.size == 2

  SUPPORTED_EXT.include?(filename_arr.last)
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
  search_files(data_path).select do |file|
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
  @files = search_files(data_path)

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

# View file's versions
get "/:filename/#{VERSIONS_DIR}" do
  file_path = File.join(data_path, params[:filename])
  versions_filepath = "#{file_path} #{VERSIONS_DIR}"

  @files = search_files(versions_filepath)

  erb :versions
end

# View a specific version of a file
get "/:versions/:filename/view" do
  file_path = File.join(data_path, params[:versions], params[:filename])

  if File.file?(file_path)
    load_file_content(file_path)
  else
    session[:message] = "#{params[:filenamever]} does not exist."
    redirect "/"
  end
end

# Create a file
post "/new" do
  prompt_login

  filename = params[:filename]
  filename_arr = split_filename(params[:filename])

  if filename.empty?
    session[:message] = "A name is required."
    status 422

    erb :new, layout: :layout
  elsif !valid_ext?(filename_arr)
    session[:message] = "Invalid file extension. Supported file extensions: "\
                        "#{SUPPORTED_EXT.join(', ')}"
    status 422

    erb :new, layout: :layout
  else
    file_path = File.join(data_path, filename)
    File.new(file_path, "w+")
    FileUtils.mkdir(File.join(data_path, "#{filename} #{VERSIONS_DIR}"))

    session[:message] = "#{filename} was created."

    redirect "/"
  end
end

# Render file creation page
get "/new" do
  prompt_login

  erb :new, layout: :layout
end

def calc_max_version(versions_filepath)
  max_version = search_files(versions_filepath).map do |file|
    split_filename(file).first.to_i
  end.max

  return -1 if max_version.nil?

  max_version
end

# Update file
post "/:filename/edit" do
  prompt_login

  file_path = File.join(data_path, params[:filename])
  versions_filepath = "#{file_path} #{VERSIONS_DIR}"

  max_version = calc_max_version(versions_filepath)

  prev_version_filename = "#{max_version + 1}."\
                          "#{split_filename(params[:filename]).last}"

  # Make a copy of the file to the previous versions folder
  FileUtils.cp(file_path, versions_filepath)

  # Rename the copy to its version number
  src = File.join(versions_filepath, params[:filename])
  dest = File.join(versions_filepath, prev_version_filename)
  FileUtils.mv(src, dest)

  # Update the contents of the file
  File.write(file_path, params[:content])

  new_filename_arr = split_filename(params[:newfilename])

  if params[:newfilename].empty?
    session[:message] = "A name is required."
    status 422

    redirect "/#{params[:filename]}/edit"
  elsif !valid_ext?(new_filename_arr)
    session[:message] = "Invalid file extension. Supported file extensions: "\
                        "#{SUPPORTED_EXT.join(', ')}"
    status 422

    redirect "/#{params[:filename]}/edit"
  else
    new_file_path = File.join(data_path, params[:newfilename])
    File.rename(file_path, new_file_path)

    session[:message] = "#{params[:newfilename]} has been updated."

    redirect "/"
  end
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

get "/img_upload" do
  prompt_login

  erb :img_upload, layout: :layout
end

post "/img_upload" do
  prompt_login

  if params[:img] && params[:img][:filename]
    filename = params[:img][:filename]
    tempfile = params[:img][:tempfile]

    FileUtils.copy(tempfile, File.join(data_path, filename))

    session[:message] = "#{filename} was uploaded."

    redirect "/"
  else
    session[:message] = "Please select an image to upload"

    erb :img_upload, layout: :layout
  end
end
