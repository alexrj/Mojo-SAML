package Mojo::SAML::IdP;

use Mojo::Base -base;

use Mojo::DOM;
use Mojo::UserAgent;
use Scalar::Util ();

my $isa = sub {
  my ($obj, $class) = @_;
  Scalar::Util::blessed($obj) && $obj->isa($class);
};
my %ns = (
  md => 'urn:oasis:names:tc:SAML:2.0:metadata',
  ds => 'http://www.w3.org/2000/09/xmldsig#',
);

has entity_id => sub {
  my $dom = shift->metadata;
  my $desc = $dom->find('md|EntityDescriptor[entityID]', %ns);
  die 'Multiple EntityDescriptor elements found' if $desc->size > 1;
  die 'No EntityDescriptor elements found' if $desc->size < 1;
  return $desc->[0]->{entityID};
};
has metadata => sub { die 'metadata is required' };
has ua => sub { Mojo::UserAgent->new };

sub entity {
  my $self = shift;
  my $id = Mojo::Util::xml_escape $self->entity_id;
  return $self->metadata->at(qq<EntityDescriptor[entityID="$id"]>) // die 'EntityDescriptor not found';
}

sub from_url {
  my ($self, $url) = @_;
  my $dom = $self->ua->get($url)->result->body;
  return $self->from_xml($dom);
}

sub from_xml {
  my ($self, $dom) = @_;
  $dom = Mojo::DOM->new->xml(1)->parse("$dom")
    unless $dom->$isa('Mojo::DOM');
  return $self->metadata($dom);
}

sub location_for {
  my ($self, $service, $binding) = @_;
  $binding = "urn:oasis:names:tc:SAML:2.0:bindings:$binding"
    unless $binding =~ /^\Qurn:oasis:names:tc:SAML:2.0:bindings:/;
  my $elem = $self->entity->at(qq!md|IDPSSODescriptor > md|${service}[Binding="$binding"][Location]!, %ns) || {};
  return $elem->{Location};
}

sub key_for {
  my ($self, $use) = @_;
  $use = Mojo::Util::xml_escape $use;
  my $s = qq!md|IDPSSODescriptor > md|KeyDescriptor[use="$use"] > ds|KeyInfo > ds|X509Data > ds|X509Certificate!;
  return undef unless my $elem = $self->entity->at($s, %ns);
  my $key = Mojo::Util::trim $elem->text;
  $key = Mojo::Util::b64_encode(Mojo::Util::b64_decode($key), ''); # clean up key
  return "-----BEGIN CERTIFICATE-----\n$key\n-----END CERTIFICATE-----\n";
}

sub _formats {
  my $self = shift;
  return $self->entity
    ->find(q!md|IDPSSODescriptor md|NameIDFormat!, %ns)
    ->map(sub{ Mojo::Util::trim $_->text });
}

sub name_id_format {
  my ($self, $format) = @_;
  my $formats = $self->_formats;
  return $formats->to_array unless defined $format;
  return $formats->first(sub{ $_ eq $format }) if $format =~ /:/;
  $format = qr/urn:oasis:names:tc:SAML:(?:2.0|1.1):nameid-format:\Q$format/;
  return $formats->first($format);
}

sub default_id_format {
  my $self = shift;
  my $formats = $self->_formats;
  return $formats->[0];
}

1;
