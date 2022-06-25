ENV["RACK_ENV"] = "test"

require "minitest/autorun"
require "rack/test"
require "fileutils"

require_relative "../cms"

class CMSTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    FileUtils.mkdir_p(data_path)
  end

  def teardown
    FileUtils.rm_rf(data_path)
  end

  def create_document(name, content = "")
    File.open(File.join(data_path, name), "w") do |file|
      file.write(content)
    end
  end

  def session
    last_request.env["rack.session"]
  end

  def admin_session
    { "rack.session" => { username: "admin" } }
  end

  def test_index
    create_document "about.md"
    create_document "changes.txt"

    get "/"

    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "about.md"
    assert_includes last_response.body, "changes.txt"
  end

  def test_viewing_text_document
    create_document "about.txt", "abc 123"

    get "/about.txt/view"

    content = File.read(File.join(data_path, "about.txt"))

    assert_equal 200, last_response.status
    assert_equal "text/plain", last_response["Content-Type"]
    assert_includes last_response.body, content
  end

  def test_bad_filename
    get "/foo.txt/view"

    assert_equal 302, last_response.status
    assert_equal "foo.txt does not exist.", session[:message]
  end

  def test_markdown
    create_document "ruby.md", "# Ruby is..."

    get "/ruby.md/view"

    assert_equal 200, last_response.status
    assert_equal "text/html;charset=utf-8", last_response["Content-Type"]
    assert_includes last_response.body, "<h1>Ruby is...</h1>"
  end

  def test_edit_file
    create_document "about.md"

    get "/about.md/edit", {}, admin_session

    assert_equal 200, last_response.status
    assert_includes last_response.body, "<textarea"
    assert_includes last_response.body, "<input type=\"submit\""
  end

  def test_edit_without_access
    create_document "about.md"

    get "/about.md/edit"

    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_update_file
    create_document "about.md"

    post "/about.md", { content: "new content" }, admin_session

    assert_equal 302, last_response.status
    assert_equal "about.md has been updated.", session[:message]

    get "/about.md/view"

    assert_equal 200, last_response.status
    assert_includes last_response.body, "new content"
  end

  def test_update_file_without_access
    create_document "about.md"

    post "/about.md", content: "new content"

    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_new_file
    get "/new", {}, admin_session

    assert_equal 200, last_response.status
    assert_includes last_response.body, "Add a new document"

    get "/new"

    assert_equal 200, last_response.status
    assert_includes last_response.body, "<input"
    assert_includes last_response.body, "<input type=\"submit"

    post "/new", filename: "new file.txt"

    assert_equal 302, last_response.status
    assert_equal "new file.txt was created.", session[:message]

    get "/"
    assert_includes last_response.body, "new file.txt"
  end

  def test_new_file_no_name
    get "/new", { filename: "foobar.txt" }, admin_session

    post "/new", filename: ""

    assert_equal 422, last_response.status
    assert_includes last_response.body, "A name is required."
  end

  def test_new_file_page_no_access
    get "/new"

    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_new_file_no_access
    post "/new", { filename: "foobar.txt" }

    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_delete
    create_document "about.txt"

    post "/about.txt/delete", {}, { "rack.session" => { logged_in: true } }
    assert_equal 302, last_response.status
    assert_equal "about.txt was deleted.", session[:message]

    get last_response["Location"]

    refute_includes last_response.body, "about.txt</a>"
  end

  def test_delete_no_access
    post "/about.txt/delete"

    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_admin_login
    get "/"

    assert_equal 200, last_response.status
    assert_includes last_response.body, "Sign In"

    get "/login"

    assert_equal 200, last_response.status
    assert_includes last_response.body, "Username"
    assert_includes last_response.body, "Password"

    post "/login", user_name: "admin", password: "secret"

    assert_equal 302, last_response.status
    assert_equal "Welcome!", session[:message]
    assert_equal "admin", session[:user_name]
    assert session[:logged_in]

    get last_response["Location"]
    assert_includes last_response.body, "Signed in as admin."
  end

  def test_login_fail
    post "/login", user_name: "abc", password: "123"

    assert_equal 422, last_response.status
    assert_includes last_response.body, "Invalid Credentials!"
    refute session[:logged_in]
  end

  def test_logout
    post "/login", user_name: "admin", password: "secret"
    get last_response["Location"]

    assert_includes last_response.body, "Sign Out"

    post "/logout"

    assert_equal 302, last_response.status
    assert_equal "You have been signed out.", session[:message]

    get last_response["Location"]

    assert_equal 200, last_response.status
    refute session[:logged_in]
    assert_includes last_response.body, "Sign In"
  end
end
