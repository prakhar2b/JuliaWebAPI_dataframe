# The API client calling functions hosted by the server.
# Runs client when invoked directly with "--runclnt" argument.
# Call `run_clnt` otherwise.
using JuliaWebAPI
using Logging
using ZMQ
using Test
using Random
using HTTP
using JSON

global_logger(ConsoleLogger(stderr, Logging.Info))

const NCALLS = 100
const APIARGS = randperm(NCALLS*4)

function printresp(apiclnt, testname, resp)
    hresp = httpresponse(apiclnt.format, resp)
    println("$(testname): $(hresp)")
end

function run_clnt(fmt, tport)
    ctx = Context()
    apiclnt = APIInvoker(tport, fmt)

    println("testing httpresponse...")
    resp = apicall(apiclnt, "testfn1", 1, 2, narg1=3, narg2=4)
    printresp(apiclnt, "testfn1", resp)

    resp = apicall(apiclnt, "testfn2", 1, 2, narg1=3, narg2=4)
    printresp(apiclnt, "testfn1", resp)

    resp = apicall(apiclnt, "testbinary", 10)
    printresp(apiclnt, "testbinary", resp)

    t = time()
    for idx in 1:100
        arg1,arg2,narg1,narg2 = APIARGS[(4*idx-3):(4*idx)]
        resp = apicall(apiclnt, "testfn1", arg1, arg2; narg1=narg1, narg2=narg2)
        @test fnresponse(apiclnt.format, resp)["data"] == (arg1 * narg1) + (arg2 * narg2)
    end
    t = time() - t
    println("time for $NCALLS calls to testfn1: $t secs @ $(t/NCALLS) per call")

    t = time()
    for idx in 1:100
        arg1,arg2,narg1,narg2 = APIARGS[(4*idx-3):(4*idx)]
        resp = apicall(apiclnt, "testfn2", arg1, arg2; narg1=narg1, narg2=narg2)
        @test fnresponse(apiclnt.format, resp) == (arg1 * narg1) + (arg2 * narg2)
    end
    t = time() - t
    println("time for $NCALLS calls to testfn2: $t secs @ $(t/NCALLS) per call")

    t = time()
    for idx in 1:100
        arrlen = APIARGS[idx]
        resp = apicall(apiclnt, "testbinary", arrlen)
        @test isa(fnresponse(apiclnt.format, resp), Array)
    end
    t = time() - t
    println("time for $NCALLS calls to testbinary: $t secs @ $(t/NCALLS) per call")

    # Test Array invocation
    println("testing array invocation...")
    resp = apicall(apiclnt, "testArray", Float64[1.0 2.0; 3.0 4.0])
    @test fnresponse(apiclnt.format, resp) == 12

    # Test unknown function call
    println("testing unknown method handling...")
    resp = apicall(apiclnt, "testNoSuchMethod", Float64[1.0 2.0; 3.0 4.0])
    @test resp["code"] == 404
    resp = apicall(apiclnt, "testArray", "no such argument")
    @test resp["code"] == 500
    @test occursin("MethodError", resp["data"])

    # Test exceptions
    println("testing server method exception handling...")
    resp = apicall(apiclnt, "testException")
    @test resp["code"] == 500
    @test occursin("testing exception handling", resp["data"]["data"])

    # Test terminate
    println("testing server termination...")
    resp = apicall(apiclnt, ":terminate")
    @test resp["code"] == 200
    @test isempty(resp["data"])

    close(ctx)
    close(tport)
end

function run_httpclnt()
    println("starting http rpc tests.")

    resp = HTTP.get("http://localhost:8888/"; status_exception=false)
    @test resp.status == 404

    resp = HTTP.get("http://localhost:8888/invalidapi"; status_exception=false)
    @test resp.status == 404

    respstr = String(HTTP.get("http://localhost:8888/testfn1/1/2"; status_exception=false).body)
    resp = JSON.parse(respstr)
    @test resp["code"] == 0
    @test resp["data"] == 5

    respstr = String(HTTP.get("http://localhost:8888/testfn1/1/2"; query=Dict(:narg1=>3,:narg2=>4), status_exception=false).body)
    resp = JSON.parse(respstr)
    @test resp["code"] == 0
    @test resp["data"] == 11

    println("testing file upload...")
    filename = "a.txt"
    postdata = """------WebKitFormBoundaryIabcPsAlNKQmowCx\r\nContent-Disposition: form-data; name="filedata"; filename="a.txt"\r\nContent-Type: text/plain\r\n\r\nLorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua. Ut enim ad minim veniam, quis nostrud exercitation ullamco laboris nisi ut aliquip ex ea commodo consequat. Duis aute irure dolor in reprehenderit in voluptate velit esse cillum dolore eu fugiat nulla pariatur. Excepteur sint occaecat cupidatat non proident, sunt in culpa qui officia deserunt mollit anim id est laborum.\n\r\n------WebKitFormBoundaryIabcPsAlNKQmowCx\r\nContent-Disposition: form-data; name="filename"\r\n\r\na.txt\r\n------WebKitFormBoundaryIabcPsAlNKQmowCx--\r\n"""
    headers = Dict("Content-Type"=>"multipart/form-data; boundary=----WebKitFormBoundaryIabcPsAlNKQmowCx")
    respstr = String(HTTP.post("http://localhost:8888/testFile"; headers=headers, body=postdata, status_exception=false).body)
    resp = JSON.parse(respstr)
    @test resp["code"] == 0
    @test resp["data"] == "5,446"

    println("testing preprocessor...")
    resp = HTTP.get("http://localhost:8888/testfn1/1/2"; headers=Dict("juliawebapi"=>"404"), status_exception=false)
    @test resp.status == 404
    println("finished http rpc tests.")
end

# run client if invoked with run flag
!isempty(ARGS) && (ARGS[1] == "--runclnt") && run_clnt(JuliaWebAPI.JSONMsgFormat(), JuliaWebAPI.ZMQTransport("127.0.0.1", 9999, ZMQ.REQ, false, ctx))
!isempty(ARGS) && (ARGS[1] == "--runhttpclnt") && run_httpclnt()
