#include "mailcart.hpp"

#include <utility>

namespace
{ // #R001: Normalize empty sender and recipient addresses.
  std::string NormalizeAddress(std::string address)
  { std::string normalized = std::move(address);
    if (normalized.empty())
    { normalized = "unknown@local";
    }
    return normalized;
  }

  // #R005: Normalize empty subjects to a default label.
  std::string NormalizeSubject(std::string subject)
  { std::string normalized = std::move(subject);
    if (normalized.empty())
    { normalized = "(no subject)";
    }
    return normalized;
  }
} // namespace

// #R010: Support plain-text body initialization via convenience constructor.
Mailcart::Mailcart(std::string sender, std::string recipient, std::string subject, std::string body)
    : Mailcart(
          std::move(sender), std::move(recipient), std::move(subject), MimeContent::PlainText(std::move(body)))
{}

Mailcart::Mailcart(std::string sender, std::string recipient, std::string subject, MimeContent mime_content)
    : sender_(NormalizeAddress(std::move(sender))),
      recipient_(NormalizeAddress(std::move(recipient))),
      subject_(NormalizeSubject(std::move(subject))),
      mime_content_(std::move(mime_content))
{}

Mailcart::~Mailcart() = default;

// #R015: Expose sender/recipient/subject/body through read-only accessors.
const std::string &Mailcart::sender() const
{ const std::string &value = sender_;
  return value;
}

const std::string &Mailcart::recipient() const
{ const std::string &value = recipient_;
  return value;
}

const std::string &Mailcart::subject() const
{ const std::string &value = subject_;
  return value;
}

const std::string &Mailcart::body() const
{ const std::string &value = mime_content_.content();
  return value;
}

// #R020: Update subject with normalization behavior.
void Mailcart::SetSubject(std::string subject)
{ subject_ = NormalizeSubject(std::move(subject));
}

// #R025: Update body through plain-text MIME conversion.
void Mailcart::SetBody(std::string body)
{ mime_content_ = MimeContent::PlainText(std::move(body));
}

const MimeContent &Mailcart::mimeContent() const
{ const MimeContent &value = mime_content_;
  return value;
}

// #R030: Support direct MIME content replacement.
void Mailcart::SetMimeContent(MimeContent mime_content)
{ mime_content_ = std::move(mime_content);
}

// #R035: Report stable base mailcart type identifier.
std::string Mailcart::type() const
{ std::string base_type("mailcart");
  return base_type;
}
