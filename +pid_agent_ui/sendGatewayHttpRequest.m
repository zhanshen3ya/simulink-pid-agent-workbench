function [payload, statusCode, statusText] = sendGatewayHttpRequest(method, url, body)
%SENDGATEWAYHTTPREQUEST Send a local gateway request without hiding HTTP errors.

arguments
    method (1, 1) string
    url (1, 1) string
    body = struct()
end

import matlab.net.URI
import matlab.net.http.HeaderField
import matlab.net.http.HTTPOptions
import matlab.net.http.MessageBody
import matlab.net.http.RequestMessage

method = upper(method);
headers = HeaderField("Accept", "application/json");
if method == "POST"
    headers(end + 1) = HeaderField("Content-Type", "application/json");
    request = RequestMessage("post", headers, MessageBody(jsonencode(body)));
elseif method == "GET"
    request = RequestMessage("get", headers);
else
    error("PIDAgent:UnsupportedGatewayMethod", ...
        "Unsupported gateway method: %s", method);
end

options = HTTPOptions("ConnectTimeout", 10, "ResponseTimeout", 360);
response = request.send(URI(url), options);
statusCode = double(response.StatusCode);
statusText = string(response.StatusLine);
payload = localDecodePayload(response.Body.Data);
end

function payload = localDecodePayload(data)
if isempty(data)
    payload = struct();
    return;
end
if isstruct(data) || iscell(data) || isnumeric(data) || islogical(data)
    payload = data;
    return;
end
if isa(data, "uint8")
    text = native2unicode(data(:).', "UTF-8");
else
    text = char(string(data));
end
try
    payload = jsondecode(text);
catch
    payload = struct("message", string(text));
end
end
