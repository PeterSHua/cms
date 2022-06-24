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

    get last_response["Location"]

    assert_equal 200, last_response.status
    assert_includes last_response.body, "foo.txt does not exist."

    get "/"
    refute_includes  last_response.body, "foo.txt does not exist."
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

    get "/about.md/edit"

    assert_equal 200, last_response.status
    assert_includes last_response.body, "<textarea"

    assert_includes last_response.body, "<input type=\"submit\""
  end

  def test_update_file
    create_document "about.md"

    post "/about.md", content: "new content"

    assert_equal 302, last_response.status

    get last_response["Location"]

    assert_equal 200, last_response.status
    assert_includes last_response.body, "about.md has been updated."

    get "/about.md/view"

    assert_equal 200, last_response.status
    assert_includes last_response.body, "new content"
  end

  def test_new_file
    get "/"

    assert_equal 200, last_response.status
    assert_includes last_response.body, "New Document"

    get "/new"

    assert_equal 200, last_response.status
    assert_includes last_response.body, "<input"
    assert_includes last_response.body, "<input type=\"submit"

    post "/new", filename: "new file.txt"

    assert_equal 302, last_response.status

    get last_response["Location"]

    assert_equal 200, last_response.status
    assert_includes last_response.body, "new file.txt was created."

    get "/"
    assert_includes last_response.body, "new file.txt"
  end

  def test_new_file_no_name
    post "/new", filename: ""

    assert_equal 422, last_response.status
    assert_includes last_response.body, "A name is required."
  end

  def test_delete
    create_document "about.txt"

    post "/about.txt/delete"
    assert_equal 302, last_response.status

    get last_response["Location"]

    assert_includes last_response.body, "about.txt was deleted."
    refute_includes last_response.body, "about.txt</a>"
  end
end
