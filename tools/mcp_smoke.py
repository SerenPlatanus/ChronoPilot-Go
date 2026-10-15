#!/usr/bin/env python3
"""Read-only MCP connection check. Does not submit or apply schedules."""
import argparse
import getpass
import json
import os
import urllib.request


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--url', default='http://127.0.0.1:8765/mcp')
    args = parser.parse_args()
    token = os.environ.get('CHRONOPILOT_MCP_TOKEN') or getpass.getpass('MCP Bearer token: ')
    sequence = 0

    def call(method, params=None):
        nonlocal sequence
        sequence += 1
        body = json.dumps({'jsonrpc': '2.0', 'id': sequence, 'method': method, 'params': params or {}}).encode()
        request = urllib.request.Request(args.url, data=body, headers={
            'Authorization': f'Bearer {token}',
            'Content-Type': 'application/json',
            'Accept': 'application/json, text/event-stream',
            'MCP-Protocol-Version': '2025-11-25',
        })
        # Never redirect an Authorization header to a different endpoint.
        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, req, fp, code, msg, headers, newurl):
                return None
        with urllib.request.build_opener(NoRedirect).open(request, timeout=180) as response:
            result = json.load(response)
        if 'error' in result:
            raise RuntimeError(result['error']['message'])
        return result['result']

    result = call('initialize', {'protocolVersion': '2025-11-25', 'capabilities': {}, 'clientInfo': {'name': 'chronopilot-smoke', 'version': '1'}})
    print('Server:', result['serverInfo']['name'], 'Protocol:', result['protocolVersion'])
    print('Tools:', ', '.join(tool['name'] for tool in call('tools/list')['tools']))
    context = call('tools/call', {'name': 'get_schedule_context', 'arguments': {}})
    if context.get('isError'):
        raise RuntimeError('Context read failed; check the app sync status.')
    data = json.loads(context['content'][0]['text'])
    print('Context read OK. Items:', len(data['items']), 'Warnings:', len(data['planningWarnings']))
    print('No draft was created and no schedule was changed.')


if __name__ == '__main__':
    main()
