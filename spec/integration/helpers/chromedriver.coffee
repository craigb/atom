_ = require "underscore-plus"
{spawn} = require "child_process"

module.exports =
  startChromedriver: (port, callback) ->
    process = spawn("chromedriver", ["--verbose", "--port=#{port}"])

    logs = []
    process.stderr.on "data", (log) -> logs.push(log.toString())
    process.stdout.on "data", (log) -> logs.push(log.toString())
    process.stdout.on "data", _.once(-> callback(process, logs))

    process.on "error", (error) ->
      throw new Error("Failed to start chromedriver: #{error.message}")

    process.on "exit", (code, signal) ->
      unless signal?
        throw new Error("""
          Chromedriver exited with status #{code}.
          Logs:

          #{logs.join("\n")}
        """)
