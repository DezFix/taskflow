import 'generated/app_localizations.dart';

/// Переводит технический код ошибки сервера в текст для сотрудника.
///
/// Сервер отдаёт код (`task_access_denied`) и русский текст для
/// отладки. Показывать сотруднику серверный текст нельзя: в
/// английском интерфейсе ошибка была бы на русском. Поэтому клиент
/// переводит код сам, а серверный текст используется только для кодов,
/// которых здесь нет.
///
/// Неизвестный код показываем как есть: так видно, что пришло с
/// сервера, и это лучше молчаливого «что-то пошло не так».
String translateErrorCode(
  String code,
  AppLocalizations l10n, {
  String? fallback,
}) {
  return switch (code) {
    'invalid_credentials' => l10n.errInvalidCredentials,
    'account_locked' => fallback ?? l10n.errRequestFailed,
    'account_disabled' => l10n.errAccountDisabled,
    'network_unreachable' => l10n.errNetworkUnreachable,
    'connection_timeout' => l10n.errConnectionTimeout,
    'certificate_error' => l10n.errCertificate,
    'token_expired' => l10n.errTokenExpired,
    'session_expired' => l10n.errTokenExpired,
    'session_revoked' => l10n.errTokenRevoked,
    'invalid_refresh' => l10n.errTokenExpired,
    'token_revoked_error' => l10n.errTokenRevoked,
    'empty_response' => l10n.errEmptyResponse,
    'network_error' => l10n.errNoConnection,
    'file_empty' => l10n.errEmptyFile,
    'empty_file' => l10n.errEmptyFile,
    'bad_url' => l10n.serverAddressRequired,
    'not_taskflow' => l10n.serverNotTaskFlow,
    'server_unreachable' => l10n.serverUnreachable,
    'unknown' => fallback ?? l10n.errUnexpected,
    _ => fallback ?? l10n.errUnexpected,
  };
}
