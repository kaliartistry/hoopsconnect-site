/// Contract-level fact state. Unknown and not-applicable are data, not errors,
/// and must never be silently replaced with zero or an empty value.
enum FactState { known, unknown, notApplicable }

sealed class Fact<T> {
  const Fact();

  FactState get state;
  T? get valueOrNull;
  String? get reasonCode;

  Map<String, Object?> toContractMap(Object? Function(T value) encodeValue);

  const factory Fact.known(T value) = KnownFact<T>;
  const factory Fact.unknown({String? reasonCode}) = UnknownFact<T>;
  const factory Fact.notApplicable({required String reasonCode}) =
      NotApplicableFact<T>;
}

final class KnownFact<T> extends Fact<T> {
  final T value;

  const KnownFact(this.value);

  @override
  FactState get state => FactState.known;

  @override
  T get valueOrNull => value;

  @override
  String? get reasonCode => null;

  @override
  Map<String, Object?> toContractMap(Object? Function(T value) encodeValue) => {
    'state': state.name,
    'value': encodeValue(value),
  };
}

final class UnknownFact<T> extends Fact<T> {
  @override
  final String? reasonCode;

  const UnknownFact({this.reasonCode});

  @override
  FactState get state => FactState.unknown;

  @override
  T? get valueOrNull => null;

  @override
  Map<String, Object?> toContractMap(Object? Function(T value) encodeValue) => {
    'reasonCode': reasonCode,
    'state': state.name,
    'value': null,
  };
}

final class NotApplicableFact<T> extends Fact<T> {
  @override
  final String reasonCode;

  const NotApplicableFact({required this.reasonCode});

  @override
  FactState get state => FactState.notApplicable;

  @override
  T? get valueOrNull => null;

  @override
  Map<String, Object?> toContractMap(Object? Function(T value) encodeValue) => {
    'reasonCode': reasonCode,
    'state': state.name,
    'value': null,
  };
}
