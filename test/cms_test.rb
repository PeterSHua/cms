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
    @original_accs = YAML.load_file(account_file_path)
  end

  def teardown
    FileUtils.rm_rf(data_path)
    File.write(account_file_path, YAML.dump(@original_accs))
  end

  def create_document(name, content = "")
    File.write(File.join(data_path, name), content)
  end

  def session
    last_request.env["rack.session"]
  end

  def admin_session
    { "rack.session" => { logged_in: true } }
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

  def test_duplicate
    create_document "about.md"

    post "/about.md/duplicate", {}, admin_session

    assert_equal 302, last_response.status

    get last_response["Location"]

    assert_includes last_response.body, "about(1).md was created"
    assert_includes last_response.body, "href=\"/about(1).md"
  end

  def test_update_file
    create_document "about.md"

    body = { newfilename: "about.md", content: "new content" }
    post "/about.md/edit", body, admin_session

    assert_equal 302, last_response.status

    get last_response["Location"]

    assert_equal 200, last_response.status
    assert_includes last_response.body, "about.md has been updated."

    get "/about.md/view"
    assert_includes last_response.body, "new content"
  end

  def test_update_file_invalid_filename
    create_document "about.md"

    post "/about.md/edit", { newfilename: "foo" }, admin_session

    assert_includes session[:message],
                    "Invalid file extension. Supported file extensions:"
  end

  def test_update_file_without_access
    create_document "about.md"

    post "/about.md/edit", content: "new content"

    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_new_file_page
    get "/new", {}, admin_session

    assert_equal 200, last_response.status
    assert_includes last_response.body, "Add a new document"

    get "/new"

    assert_equal 200, last_response.status
    assert_includes last_response.body, "<input"
    assert_includes last_response.body, "<input type=\"submit"
  end

  def test_new_file
    post "/new", { filename: "new file.txt" }, admin_session

    assert_equal 302, last_response.status
    assert_equal "new file.txt was created.", session[:message]

    get "/"
    assert_includes last_response.body, "new file.txt"
  end

  def test_new_file_no_name
    get "/new", {}, admin_session

    post "/new", filename: ""

    assert_equal 422, last_response.status
    assert_includes last_response.body, "A name is required."
  end

  def test_new_file_unsupported_ext
    get "/new", {}, admin_session

    post "/new", filename: "foo.bar"

    assert_equal 422, last_response.status
    assert_includes last_response.body,
                    "Invalid file extension. Supported file extensions:"
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

  def test_dup_file_no_access
    create_document "about.md"

    post "/about.md/duplicate"

    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_dup_file
    get "/new", {}, admin_session

    create_document "about.md"

    post "/about.md/duplicate"

    assert_equal 302, last_response.status
    assert_equal "about(1).md was created.", session[:message]

    get last_response["Location"]

    assert_includes last_response.body, "about(1).md"
  end

  def test_dup_file_multiple
    get "/new", {}, admin_session

    create_document "about.md"

    post "/about.md/duplicate"
    get last_response["Location"]

    post "/about.md/duplicate"

    assert_equal "about(2).md was created.", session[:message]

    get last_response["Location"]

    assert_includes last_response.body, "about(1).md"
    assert_includes last_response.body, "about(2).md"
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

    post "/login", { username: "admin", password: "secret" }

    assert_equal 302, last_response.status
    assert_equal "Welcome!", session[:message]
    assert_equal "admin", session[:username]
    assert session[:logged_in]

    get last_response["Location"]
    assert_includes last_response.body, "Signed in as admin."
  end

  def test_login_fail
    post "/login", { username: "admin", password: "foobar" }

    assert_equal 422, last_response.status
    assert_includes last_response.body, "Invalid Credentials!"
    refute session[:logged_in]
  end

  def test_logout
    post "/login", { username: "admin", password: "secret" }
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

  def test_register_already_logged_in
    post "/register", { username: "john", password: "deer" }, admin_session

    assert_equal 302, last_response.status
    assert_equal "You're already logged in.", session[:message]
  end

  def test_register_acc_exists
    post "/register", { username: "admin", password: "admin" }

    assert_equal 422, last_response.status
    assert_includes last_response.body, "That account name already exists."
  end

  def test_register_short_username
    post "/register", { username: "joh", password: "deer" }

    assert_equal 422, last_response.status
    assert_includes last_response.body,
                    "Username must consist of only letters and numbers, "\
                    "and must be between 4-10 characters."
  end

  def test_register_long_username
    post "/register", { username: "johnjohnjohn", password: "deer" }

    assert_equal 422, last_response.status
    assert_includes last_response.body,
                    "Username must consist of only letters and numbers, "\
                    "and must be between 4-10 characters."
  end

  def test_register_invalid_chars_username
    post "/register", { username: "j[]hn", password: "deer" }

    assert_equal 422, last_response.status
    assert_includes last_response.body,
                    "Username must consist of only letters and numbers, "\
                    "and must be between 4-10 characters."
  end

  def test_register_short_password
    post "/register", { username: "john", password: "doe" }

    assert_equal 422, last_response.status
    assert_includes last_response.body,
                    "Password must be between 4-10 characters and cannot "\
                    "contain spaces."
  end

  def test_register_long_password
    post "/register", { username: "john", password: "deerdeerdeer" }

    assert_equal 422, last_response.status
    assert_includes last_response.body,
                    "Password must be between 4-10 characters and cannot "\
                    "contain spaces."
  end

  def test_register_invalid_chars_password
    post "/register", { username: "john", password: "d e e r" }

    assert_equal 422, last_response.status
    assert_includes last_response.body,
                    "Password must be between 4-10 characters and cannot "\
                    "contain spaces."
  end

  def test_register
    get "/register", {}

    assert_equal 200, last_response.status
    assert_includes last_response.body, "Username"
    assert_includes last_response.body, "Password"

    post "/register", { username: "john", password: "deer" }

    assert_equal 302, last_response.status
    assert_equal "Your account has been registered.", session[:message]
    assert_equal "john", session[:username]
    assert session[:logged_in]

    post "/logout"
    refute session[:logged_in]
    post "/login", { username: "john", password: "deer" }

    assert session[:logged_in]
  end

  def test_img_upload
    get "/img_upload", {}, admin_session

    assert_equal 200, last_response.status

    filename = "ruby.png"
    dir = File.expand_path("../#{TEST_DIRECTORY}", __dir__)

    file = {
      filename: "ruby.png",
      tempfile: File.join(dir, filename)
    }

    post "/img_upload", { img: file }

    assert_equal 302, last_response.status
    assert_equal "#{filename} was uploaded.", session[:message]

    get last_response["Location"]

    assert_includes last_response.body, "ruby.png"
  end

  def test_img_upload_no_access
    get "/img_upload", {}

    assert_equal 302, last_response.status
    assert_equal "You must be signed in to do that.", session[:message]
  end

  def test_img_upload_no_file
    post "/img_upload", {}, admin_session

    assert_equal 200, last_response.status
    assert_includes last_response.body, "Please select an image to upload"
  end
end
