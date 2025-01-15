/**
 * Test SSE-based MCP server for the unit tests in the package.
 *   - Serves a Server-Sent Events (SSE) endpoint at `/sse`
 *   - Sends an "endpoint" event to the SSE client upon connection, containing a POST URL for subsequent messages
 *   - Receives POST data at the returned URL (hosted over localhost), example path: `/message?sessionId=...`. Data is echo'd automatically
 *   - Logs connect/disconnect/error events to the console
 *   - Test messages:
 *       - "client::disconnect" -> the downchannel is disconnected
 *       - "client::badMessage" -> malformed payload is sent on the downchannel
 *       - "client::changeEndpoint" -> endpoint will be updated (with a new sessionId)
 *
 * Usage:
 *   1. Run `node sse.js`
 *   2. Your SSE client (Swift, or other) connects to `http://127.0.0.1:3000/sse`
 *   3. The server sends an "endpoint" event telling the client how to POST messages
 *   4. You can send messages to the server by making a POST request to `/message?sessionId=XXX`
 */

const http = require("http");
const { randomUUID } = require("crypto");

/**
 * @typedef {Object} SSEClient
 * @property {string} sessionId - Unique session identifier
 * @property {string} host - The host of the POST url for this client
 * @property {http.ServerResponse} response - The Node.js response that we write SSE data into
 */

/** @type {Map<string, SSEClient>} */
const sseClients = new Map();

/**
 * Creates an HTTP server listening on port 3000.
 * - GET /sse: opens an SSE stream, sets up an endpoint event
 * - POST /message?sessionId=... : sends data to a specific SSE client
 */
const server = http.createServer((req, res) => {
    const url = new URL(req.url, `http://${req.headers.host}`);
    const { pathname, searchParams } = url;

    // SSE Endpoint
    if (req.method === "GET" && pathname === "/sse") {
        handleSSEConnection(req, res);
        return;
    }

    // Incoming message for SSE client
    if (req.method === "POST" && pathname === "/message") {
        handlePostMessage(req, res, searchParams);
        return;
    }

    // Otherwise, 404
    res.writeHead(404, { "Content-Type": "text/plain" });
    res.end("Not found\n");
});

/**
 * Returns the endpoint URL for the given SSE client.
 * @param {SSEClient} sseClient - The SSE client, where the endpoint URL is derived from
 */
function sendEndpointEvent(sseClient) {
    sendSSEEvent(sseClient.response, "endpoint", `http://${sseClient.host}/message?sessionId=${sseClient.sessionId}`);
}

/**
 * Handles a new SSE connection on /sse.
 *
 * @param {http.IncomingMessage} req - The HTTP request
 * @param {http.ServerResponse} res - The HTTP response (to be used as SSE stream)
 */
function handleSSEConnection(req, res) {
    const sessionId = randomUUID();

    // pre-headers
    res.writeHead(200, {
        "Content-Type": "text/event-stream",
        "Cache-Control": "no-cache",
        Connection: "keep-alive",
    });

    /** @type {SSEClient} */
    const sseClient = {
        host: req.headers.host,
        sessionId,
        response: res,
    };
    sseClients.set(sessionId, sseClient);

    console.log(`[SSE] Client connected: sessionId = ${sessionId}`);

    // Send the endpoint URL to the client
    sendEndpointEvent(sseClient);

    // listen for disconnect
    req.on("close", () => {
        console.log(`[SSE] Client disconnected: sessionId = ${sessionId}`);
        sseClients.delete(sessionId);
    });

    // simulate keep-alive / activity
    setInterval(() => {
        sendSSEEvent(res, "message", JSON.stringify({ time: Date.now() }));
    }, 5000);
}

/**
 * Handles a POST request to /message?sessionId=...
 * Reads the entire request body as text, then sends it as "message" event to the matching SSE client.
 *
 * @param {http.IncomingMessage} req - The HTTP request
 * @param {http.ServerResponse} res - The HTTP response
 * @param {URLSearchParams} searchParams - Query parameters
 */
function handlePostMessage(req, res, searchParams) {
    const sessionId = searchParams.get("sessionId");
    if (!sessionId) {
        res.writeHead(400, { "Content-Type": "text/plain" });
        return res.end("Missing sessionId\n");
    }

    const sseClient = sseClients.get(sessionId);
    if (!sseClient) {
        res.writeHead(404, { "Content-Type": "text/plain" });
        return res.end("No SSE client with that sessionId\n");
    }

    let bodyData = "";
    req.on("data", (chunk) => {
        bodyData += chunk;
    });

    req.on("end", () => {
        // we have the full response
        console.log(`[SSE] Received POST for sessionId=${sessionId}, data="${bodyData}"`);
        const ack = () => {
            res.writeHead(202, { "Content-Type": "text/plain" });
            res.end("ack\n");
        };

        // test messages
        if (bodyData.includes("client::disconnect")) {
            console.log(`[SSE] Disconnecting sessionId=${sessionId}`);
            sseClient.response.end();
            sseClients.delete(sessionId);
            return;
        } else if (bodyData.includes("client::badMessage")) {
            console.log(`[SSE] Sending bad message to sessionId=${sessionId}`);
            res.writeHead(500, { "Content-Type": "text/plain" });
            res.end("ERROR: NOT OK");
            return;
        } else if (bodyData.includes("client::changeEndpoint")) {
            console.log(`[SSE] Changing endpoint for sessionId=${sessionId}`);
            // update sessionId to change the endpoint
            sseClient.sessionId = randomUUID();
            sendEndpointEvent(sseClient);
            ack();
            return;
        }
        ack();
    });

    req.on("error", (err) => {
        console.error(`[SSE] Error reading POST data: ${err}`);
    });
}

/**
 * Sends an SSE event to the given response.
 *
 * @param {http.ServerResponse} res - The response to write to
 * @param {string} eventName - The SSE event name (e.g. "message", "endpoint")
 * @param {string} data - The event payload
 */
function sendSSEEvent(res, eventName, data) {
    try {
        // SSE format being followed is each event results in two lines:
        //   event: <eventName>
        //   data: <string data>
        //   [blank line]
        res.write(`event: ${eventName}\n`);
        res.write(`data: ${data}\n\n`);
    } catch (error) {
        console.error(`[SSE] Error sending SSE event: ${error}`);
        res.destroy(error);
    }
}

server.listen(3000, "127.0.0.1", () => {
    console.log("[SSE] Server listening on http://127.0.0.1:3000");
});
