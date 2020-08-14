class SecureMailing
  include ::Mixin::HasBackends

  def self.incoming(mail)
    active_backends.each do |backend|
      "#{backend}::Incoming".constantize.process(mail)
    end
  end

  def self.retry(article)
    active_backends.each do |backend|
      "#{backend}::Retry".constantize.process(article)
    end
  end

  def self.outgoing(mail, security)
    active_backends.each do |backend|
      "#{backend}::Outgoing".constantize.process(mail, security)
    end
  end

  def self.active_backends
    backends.select(&:active?)
  end
end
