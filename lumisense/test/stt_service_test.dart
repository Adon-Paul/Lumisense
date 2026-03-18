import 'package:flutter_test/flutter_test.dart';
import 'package:lumisense/services/stt_service.dart';

void main() {
  group('SttService.mapToCommand', () {
    test('maps read phrases', () {
      expect(SttService.mapToCommand('read this text'), VoiceCommand.readText);
      expect(SttService.mapToCommand('scan label'), VoiceCommand.readText);
    });

    test('maps identify phrases', () {
      expect(SttService.mapToCommand('identify object'), VoiceCommand.identifyObjects);
      expect(SttService.mapToCommand('what is this'), VoiceCommand.identifyObjects);
    });

    test('maps describe phrases', () {
      expect(SttService.mapToCommand('describe scene'), VoiceCommand.describeScene);
      expect(SttService.mapToCommand('what do you see'), VoiceCommand.describeScene);
    });

    test('maps utility phrases', () {
      expect(SttService.mapToCommand('help'), VoiceCommand.help);
      expect(SttService.mapToCommand('emergency now'), VoiceCommand.sos);
      expect(SttService.mapToCommand('stop talking'), VoiceCommand.stop);
    });

    test('returns unknown for unrelated speech', () {
      expect(SttService.mapToCommand('banana umbrella'), VoiceCommand.unknown);
    });
  });
}
