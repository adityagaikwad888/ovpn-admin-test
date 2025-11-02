{{- range $server := .Hosts }}
remote {{ $server.Host }} {{ $server.Port }} {{ $server.Protocol }}
{{- end }}

verb 4
client
nobind
dev tun
cipher AES-256-GCM
key-direction 1
redirect-gateway def1
persist-key
persist-tun
remote-cert-tls server
auth-user-pass
script-security 2
up /etc/openvpn/update-resolv-conf
down /etc/openvpn/update-resolv-conf

<cert>
{{ .Cert -}}
</cert>
<key>
{{ .Key -}}
</key>
<ca>
{{ .CA -}}
</ca>
<tls-auth>
{{ .TLS -}}
</tls-auth>
