# The API server serving functions from srvrfn.jl.
# Runs server in blocking mode when invoked directly with "--runsrvr" argument.
# Call `run_srvr` to start server otherwise.
using JuliaWebAPI
using Logging
using Sockets
using ZMQ
using JSON
using HTTP

include("srvrfn.jl")

const SRVR_ADDR = "tcp://127.0.0.1:9999"
const JSON_RESP_HDRS = Dict{String,String}("Content-Type" => "application/json; charset=utf-8")
const BINARY_RESP_HDRS = Dict{String,String}("Content-Type" => "application/octet-stream")

function run_srvr(fmt, tport, async=false, openaccess=false)
    global_logger(SimpleLogger(open("apisrvr_test.log", "a"), Logging.Info))
    @info("queue is at $SRVR_ADDR")

    api = APIResponder(tport, fmt, nothing, openaccess)
    @info("responding with: $api")

    register(api, testfn1; resp_json=true, resp_headers=JSON_RESP_HDRS)
    register(api, testfn2)
    register(api, testbinary; resp_headers=BINARY_RESP_HDRS)
    register(api, testArray)
    register(api, testFile; resp_json=true, resp_headers=JSON_RESP_HDRS)
    register(api, testException; resp_json=true, resp_headers=JSON_RESP_HDRS)

    process(api; async=async)
end

function test_preproc(req::HTTP.Request)
    respcode = HTTP.header(req, "juliawebapi")
    isempty(respcode) ? JuliaWebAPI.default_preproc(req) : HTTP.Response(parse(Int, respcode))
end

function run_httprpcsrvr(fmt, tport, async=false)
    run_srvr(fmt, tport, true, true)
    apiclnt = APIInvoker(ZMQTransport(SRVR_ADDR, REQ, false), fmt)
    if async
        @async run_http(apiclnt, 8888, test_preproc; reuseaddr=true)
    else
        run_http(apiclnt, 8888, test_preproc; reuseaddr=true)
    end
end

function wait_for_httpsrvr()
    while true
        try
            sock = connect("localhost", 8888)
            close(sock)
            return
        catch
            @info("waiting for httpserver to come up at port 8888...")
            sleep(5)
        end
    end
end

# run in blocking mode if invoked with run flag
!isempty(ARGS) && (ARGS[1] == "--runsrvr") && run_srvr(JuliaWebAPI.JSONMsgFormat(), JuliaWebAPI.ZMQTransport(SRVR_ADDR, ZMQ.REP, true), false)

# run http rpc server if invoked with flag
!isempty(ARGS) && (ARGS[1] == "--runhttprpcsrvr") && run_httprpcsrvr(JuliaWebAPI.JSONMsgFormat(), JuliaWebAPI.ZMQTransport(SRVR_ADDR, ZMQ.REP, true), false)
