require "tilt/erubis"
require "sinatra"
require "sinatra/reloader"
require "sinatra/content_for"
require "redcarpet"

root = File.expand_path("..", __FILE__)

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

before do

end

helpers do

end

# File index
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
  file_path = File.join(data_path, params[:filename])

  @filename = params[:filename]
  @content = File.read(file_path)

  erb :edit, layout: :layout
end

# Create a file
post "/new" do
  # Create the file
  # Validate user input

  file_name = params[:filename]

  if file_name.empty?
    session[:message] = "A name is required"

    redirect "/new"
  else
    file_path = File.join(data_path, file_name)
    File.new(file_path, "w+")

    session[:message] = "#{file_name} was created"

    redirect "/"
  end
end

# Write to file
post "/:filename" do
  file_path = File.join(data_path, params[:filename])

  f = File.open(file_path, 'w')
  f.write(params[:content])
  f.close

  session[:message] = "#{params[:filename]} has been updated."

  redirect "/"
end

# Create a file
get "/new" do
  erb :new, layout: :layout
end
