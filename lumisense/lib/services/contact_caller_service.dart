import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:url_launcher/url_launcher.dart';

/// Result of a contact search.
class ContactSearchResult {
  const ContactSearchResult({
    required this.found,
    this.phoneNumber,
    this.displayName,
    this.matchCount = 0,
  });

  final bool found;
  final String? phoneNumber;
  final String? displayName;
  final int matchCount;

  /// TTS-friendly description.
  String get spokenSummary {
    if (!found) return 'No matching contact found.';
    if (matchCount > 1) {
      return 'Found $matchCount contacts matching that name. '
          'Calling ${displayName ?? "unknown"}.';
    }
    return 'Calling ${displayName ?? "unknown"}.';
  }
}

/// Searches device contacts by name and initiates phone calls.
///
/// Uses `flutter_contacts` v2 for contact access and `url_launcher` for dialling.
class ContactCallerService {
  const ContactCallerService();

  /// Returns true if the app has contacts permission.
  Future<bool> hasPermission() async {
    return FlutterContacts.permissions.has(PermissionType.read);
  }

  /// Requests contacts permission. Returns true if granted.
  Future<bool> requestPermission() async {
    final PermissionStatus status =
        await FlutterContacts.permissions.request(PermissionType.read);
    return status == PermissionStatus.granted ||
        status == PermissionStatus.limited;
  }

  /// Searches contacts by [query] (fuzzy name matching).
  ///
  /// Returns the best match, or a not-found result.
  Future<ContactSearchResult> searchAndPrepareCall(String query) async {
    try {
      final bool granted = await requestPermission();
      if (!granted) {
        return const ContactSearchResult(
          found: false,
          displayName: 'Permission denied',
        );
      }

      // Fetch all contacts with phone numbers.
      final List<Contact> contacts = await FlutterContacts.getAll(
        properties: <ContactProperty>{ContactProperty.phone, ContactProperty.name},
      );

      final String lowerQuery = query.toLowerCase().trim();

      // Exact display name match first.
      List<Contact> matches = contacts.where((Contact c) {
        return (c.displayName ?? '').toLowerCase() == lowerQuery;
      }).toList();

      // Contains match.
      if (matches.isEmpty) {
        matches = contacts.where((Contact c) {
          return (c.displayName ?? '').toLowerCase().contains(lowerQuery);
        }).toList();
      }

      // First name match.
      if (matches.isEmpty) {
        matches = contacts.where((Contact c) {
          final String firstName = (c.name?.first ?? '').toLowerCase();
          return firstName == lowerQuery || firstName.contains(lowerQuery);
        }).toList();
      }

      // Last name match.
      if (matches.isEmpty) {
        matches = contacts.where((Contact c) {
          final String lastName = (c.name?.last ?? '').toLowerCase();
          return lastName == lowerQuery || lastName.contains(lowerQuery);
        }).toList();
      }

      if (matches.isEmpty) {
        return const ContactSearchResult(found: false);
      }

      // Pick the best match.
      final Contact best = matches.first;

      // Find a phone number.
      String? phoneNumber;
      if (best.phones.isNotEmpty) {
        // Prefer mobile numbers.
        final Phone? mobile = best.phones.cast<Phone?>().firstWhere(
          (Phone? p) =>
              p != null &&
              (p.label.label == PhoneLabel.mobile ||
               p.label.label == PhoneLabel.main),
          orElse: () => null,
        );
        phoneNumber = (mobile ?? best.phones.first).number;
      }

      if (phoneNumber == null || phoneNumber.isEmpty) {
        return ContactSearchResult(
          found: true,
          displayName: best.displayName ?? 'Unknown',
          phoneNumber: null,
          matchCount: matches.length,
        );
      }

      return ContactSearchResult(
        found: true,
        displayName: best.displayName ?? 'Unknown',
        phoneNumber: phoneNumber,
        matchCount: matches.length,
      );
    } catch (e) {
      debugPrint('ContactCallerService: search error: $e');
      return const ContactSearchResult(found: false);
    }
  }

  /// Dials [phoneNumber] using the system phone app.
  Future<bool> dialNumber(String phoneNumber) async {
    final Uri uri = Uri(scheme: 'tel', path: phoneNumber);
    try {
      return await launchUrl(uri);
    } catch (e) {
      debugPrint('ContactCallerService: dial error: $e');
      return false;
    }
  }

  /// Searches for a contact and immediately initiates a call.
  Future<ContactSearchResult> callContact(String query) async {
    final ContactSearchResult result = await searchAndPrepareCall(query);
    if (result.found && result.phoneNumber != null) {
      await dialNumber(result.phoneNumber!);
    }
    return result;
  }
}
