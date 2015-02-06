# These tests are excluded by default. To run them from the command line:
#
# ATOM_INTEGRATION_TESTS_ENABLED=true apm test
return unless process.env.ATOM_INTEGRATION_TESTS_ENABLED

os = require "os"
fs = require "fs"
path = require "path"
remote = require "remote"
temp = require("temp").track()
{startChromedriver} = require("./helpers/chromedriver")
{spawnSync} = require "child_process"
{Builder, By} = require "../../build/node_modules/selenium-webdriver"

AtomPath = remote.process.argv[0]
AtomLauncherPath = path.join(__dirname, "helpers", "atom-launcher.sh")
SocketPath = path.join(os.tmpdir(), "atom-integration-test.sock")
ChromeDriverPort = 9515

describe "Starting Atom", ->
  [chromedriverProcess, driver, tempDirPath] = []

  beforeEach ->
    tempDirPath = temp.mkdirSync("empty-dir")

    waitsFor "chromedriver to start", (done) ->
      startChromedriver ChromeDriverPort, (process) ->
        chromedriverProcess = process
        done()

  afterEach ->
    waitsFor "driver to quit", (done) ->
      driver.quit().thenFinally ->
        chromedriverProcess.kill()
        done()

  startAtom = (args...) ->
    driver = new Builder()
      .usingServer("http://localhost:#{ChromeDriverPort}")
      .withCapabilities(
        chromeOptions:
          binary: AtomLauncherPath
          args: [
            "atom-path=#{AtomPath}"
            "atom-args=#{args.join(" ")}"
            "dev"
            "safe"
            "user-data-dir=#{temp.mkdirSync('integration-spec-')}"
            "socket-path=#{SocketPath}"
          ]
      )
      .forBrowser('atom')
      .build()

    driver.wait ->
      driver.getTitle().then (title) -> title.indexOf("Atom") >= 0

  startAnotherAtom = (args...) ->
    spawnSync(AtomPath, args.concat([
      "--dev",
      "--safe",
      "--socket-path=#{SocketPath}"
    ]))

  wait = (done) -> waitsFor(done, 15000)

  describe "opening paths via commmand-line arguments", ->
    tempFilePath = null

    beforeEach ->
      tempFilePath = path.join(tempDirPath, "an-existing-file")
      fs.writeFileSync(tempFilePath, "This was already here.")

    it "reuses existing windows when directories are reopened", ->
      wait (done) ->

        # Opening a new file creates one window with one empty text editor.
        startAtom(path.join(tempDirPath, "new-file"))

        driver.getAllWindowHandles().then (handles) ->
          expect(handles.length).toBe 1
        driver.executeScript(-> atom.workspace.getActivePane().getItems().length).then (length) ->
          expect(length).toBe 1
        driver.executeScript(-> atom.workspace.getActiveTextEditor().getText()).then (text) ->
          expect(text).toBe("")
        driver.findElement(By.tagName("atom-text-editor")).sendKeys("Hello world!")
        driver.executeScript(-> atom.workspace.getActiveTextEditor().getText()).then (text) ->
          expect(text).toBe "Hello world!"

        # Opening an existing file in the same directory reuses the window and
        # adds a new tab for the file.
        driver.call -> startAnotherAtom(tempFilePath)
        driver.wait ->
          driver.executeScript(-> atom.workspace.getActivePane().getItems().length).then (length) ->
            length is 2
        driver.executeScript(-> atom.workspace.getActiveTextEditor().getText()).then (text) ->
          expect(text).toBe "This was already here."

        # Opening a different directory creates a second window.
        driver.call -> startAnotherAtom(temp.mkdirSync("another-empty-dir"))
        driver.wait ->
          driver.getAllWindowHandles().then (handles) ->
            handles.length is 2
        driver.getAllWindowHandles().then (handles) ->
          driver.switchTo().window(handles[1])
        driver.executeScript(-> atom.workspace.getActivePane().getItems().length).then (length) ->
          expect(length).toBe(0)

        driver.call(done)
