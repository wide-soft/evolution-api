import http.client
import ssl
import json
import sys

def https_post(host, path, data, token=None, headers=None):
    context = ssl.create_default_context()
    conn = http.client.HTTPSConnection(host, context=context)
    try:
        body = json.dumps(data)
        if headers is None:
            headers = {}
        headers.setdefault("Content-Type", "application/json")
        if token:
            headers["Authorization"] = f"Bearer {token}"
        conn.request("POST", path, body=body, headers=headers)
        response = conn.getresponse()
        resp_data = response.read()
        return response.status, resp_data
    except http.client.HTTPException as e:
        print(f"HTTP error: {e}")
        return None, None
    except ssl.SSLError as e:
        print(f"SSL error: {e}")
        return None, None
    except json.JSONDecodeError as e:
        print(f"JSON decode error: {e}")
        return None, None
    finally:
        conn.close()

def main():
    args = sys.argv
    if len(args) != 5:
        print("api_key | Usage: python3 api_key.py <host> <path> <payload_json> <bearer_token>")
        sys.exit(1)

    host = args[1]
    path = args[2]
    try:
        payload = json.loads(str(args[3]).strip("'"))
    except json.JSONDecodeError as e:
        print("api_key | Payload must be a valid JSON string.")
        sys.exit(1)
    token = args[4]
    status, resp = https_post(host, path, payload, token)
    decoded_resp = resp.decode() if resp else "No response"
    try:
        if status != 200:
            print(f"api_key | Error: {decoded_resp.get('erro', 'Unknown error')}")
            sys.exit(1)
        else:
            print(f"api_key | Status: {status}, Response: {resp.decode()}")
    except json.JSONDecodeError:
        print("api_key | Failed to decode response as JSON.")
        sys.exit(1)

if __name__ == "__main__":
    main()
