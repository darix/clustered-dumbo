{%- set server_cert_filename = "/etc/step/certs/generic.host.full.pem" %}
{%- set client_cert_filename = "/etc/step/certs/generic.user.full.pem" %}
{%- set ca_certs_filename    = pillar.step.client_config.ca.root_cert.path %}

etcd:
  client_port:   2379
  peer_port:     2380
  protocol:      https
  server_cert:   {{ server_cert_filename }}
  client_cert:   {{ client_cert_filename }}
  ca_cert:       {{ ca_certs_filename }}