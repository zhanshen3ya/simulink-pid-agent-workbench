function request = buildGatewayRequest(method, body)
%BUILDGATEWAYREQUEST Build a version-compatible local gateway request.

arguments
    method (1, 1) string
    body = struct()
end

import matlab.net.http.HeaderField
import matlab.net.http.MessageBody
import matlab.net.http.RequestMessage
import matlab.net.http.RequestMethod

method = upper(method);
headers = HeaderField("Accept", "application/json");
if method == "POST"
    headers(end + 1) = HeaderField("Content-Type", "application/json");
    request = RequestMessage(RequestMethod.POST, headers, ...
        MessageBody(body));
elseif method == "GET"
    request = RequestMessage(RequestMethod.GET, headers);
else
    error("PIDAgent:UnsupportedGatewayMethod", ...
        "Unsupported gateway method: %s", method);
end
end
