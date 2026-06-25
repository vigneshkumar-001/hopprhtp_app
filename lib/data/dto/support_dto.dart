import '../../core/network/json.dart';

/// Support contact channels surfaced in the Help centre.
class SupportContact {
  const SupportContact({
    required this.email,
    required this.phone,
    required this.whatsapp,
    required this.hours,
  });

  final String email;
  final String phone;
  final String whatsapp;
  final String hours;

  factory SupportContact.fromJson(Map<String, dynamic> m) => SupportContact(
        email: asString(m['email']),
        phone: asString(m['phone']),
        whatsapp: asString(m['whatsapp']),
        hours: asString(m['hours']),
      );
}

/// A single frequently-asked question + answer.
class SupportFaq {
  const SupportFaq({
    required this.question,
    required this.answer,
    this.category,
  });

  final String question;
  final String answer;
  final String? category;

  factory SupportFaq.fromJson(Map<String, dynamic> m) => SupportFaq(
        question: asString(m['question']),
        answer: asString(m['answer']),
        category: asStringOrNull(m['category']),
      );
}

/// The Help-centre payload: contact channels + curated FAQs.
class SupportOverview {
  const SupportOverview({required this.contact, required this.faqs});

  final SupportContact contact;
  final List<SupportFaq> faqs;

  factory SupportOverview.fromJson(Map<String, dynamic> m) => SupportOverview(
        contact: SupportContact.fromJson(asMap(m['contact'])),
        faqs: asList(m['faqs'])
            .map((e) => SupportFaq.fromJson(asMap(e)))
            .toList(growable: false),
      );
}

/// A submitted support request.
class SupportTicket {
  const SupportTicket({
    required this.id,
    required this.code,
    required this.category,
    required this.subject,
    required this.message,
    required this.status,
    this.createdAt,
  });

  final String id;
  final String code;
  final String category;
  final String subject;
  final String message;
  final String status;
  final DateTime? createdAt;

  factory SupportTicket.fromJson(Map<String, dynamic> m) => SupportTicket(
        id: asString(m['id'] ?? m['_id']),
        code: asString(m['code']),
        category: asString(m['category']),
        subject: asString(m['subject']),
        message: asString(m['message']),
        status: asString(m['status'], 'open'),
        createdAt: asDateTime(m['createdAt']),
      );
}
