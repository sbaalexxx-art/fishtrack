class CacheResult<T> {
  const CacheResult(this.value, {this.isStaleFallback = false});

  final T value;
  final bool isStaleFallback;
}

class TimedCache<T> {
  TimedCache({required this.duration, DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final Duration duration;
  final DateTime Function() _clock;
  T? _value;
  DateTime? _savedAt;
  Future<CacheResult<T>>? _activeRequest;

  bool get hasValue => _value != null;
  bool get isFresh =>
      _value != null &&
      _savedAt != null &&
      _clock().difference(_savedAt!) < duration;

  Future<CacheResult<T>> get(
    Future<T> Function() loader, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && isFresh) return CacheResult<T>(_value as T);
    if (_activeRequest case final request?) return request;

    final request = _load(loader);
    _activeRequest = request;
    try {
      return await request;
    } finally {
      if (identical(_activeRequest, request)) _activeRequest = null;
    }
  }

  Future<CacheResult<T>> _load(Future<T> Function() loader) async {
    try {
      final value = await loader();
      _value = value;
      _savedAt = _clock();
      return CacheResult<T>(value);
    } on Exception {
      final value = _value;
      if (value != null) {
        return CacheResult<T>(value, isStaleFallback: true);
      }
      rethrow;
    }
  }

  void clear() {
    _value = null;
    _savedAt = null;
    _activeRequest = null;
  }
}
