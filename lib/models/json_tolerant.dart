
library;

Map<String, dynamic> asJsonMap(Object? raw) {
  if (raw is Map) {
    final Map<String, dynamic> out = <String, dynamic>{};
    raw.forEach((Object? key, Object? value) {
      if (key is String) {
        out[key] = value;
      }
    });
    return out;
  }
  return <String, dynamic>{};
}

double readDouble(Map<String, dynamic> json, String key, double fallback) {
  final Object? raw = json[key];
  if (raw is num) {
    final double value = raw.toDouble();

    if (value.isFinite) {
      return value;
    }
    return fallback;
  }
  if (raw is String) {
    final double? parsed = double.tryParse(raw.replaceAll(',', '.'));
    if (parsed != null && parsed.isFinite) {
      return parsed;
    }
  }
  return fallback;
}

double? readNullableDouble(Map<String, dynamic> json, String key) {
  final Object? raw = json[key];
  if (raw is num) {
    final double value = raw.toDouble();
    return value.isFinite ? value : null;
  }
  if (raw is String) {
    final double? parsed = double.tryParse(raw.replaceAll(',', '.'));
    if (parsed != null && parsed.isFinite) {
      return parsed;
    }
  }
  return null;
}

int readInt(Map<String, dynamic> json, String key, int fallback) {
  final Object? raw = json[key];
  if (raw is int) {
    return raw;
  }
  if (raw is num && raw.isFinite) {
    return raw.round();
  }
  if (raw is String) {
    final int? parsed = int.tryParse(raw);
    if (parsed != null) {
      return parsed;
    }
    final double? asDouble = double.tryParse(raw);
    if (asDouble != null && asDouble.isFinite) {
      return asDouble.round();
    }
  }
  return fallback;
}

bool readBool(Map<String, dynamic> json, String key, bool fallback) {
  final Object? raw = json[key];
  if (raw is bool) {
    return raw;
  }
  if (raw is num) {
    return raw != 0;
  }
  if (raw is String) {
    final String lower = raw.toLowerCase();
    if (lower == 'true' || lower == '1') {
      return true;
    }
    if (lower == 'false' || lower == '0') {
      return false;
    }
  }
  return fallback;
}

String readString(Map<String, dynamic> json, String key, String fallback) {
  final Object? raw = json[key];
  if (raw is String && raw.trim().isNotEmpty) {
    return raw;
  }
  return fallback;
}

String? readNullableString(Map<String, dynamic> json, String key) {
  final Object? raw = json[key];
  if (raw is String && raw.trim().isNotEmpty) {
    return raw;
  }
  return null;
}

T readEnum<T extends Enum>(
  Map<String, dynamic> json,
  String key,
  List<T> values,
  T fallback,
) {
  final Object? raw = json[key];
  if (raw is String) {
    for (final T value in values) {
      if (value.name == raw) {
        return value;
      }
    }
  }
  if (raw is int && raw >= 0 && raw < values.length) {
    return values[raw];
  }
  return fallback;
}

DateTime readDateTime(
  Map<String, dynamic> json,
  String key,
  DateTime fallback,
) {
  return readNullableDateTime(json, key) ?? fallback;
}

DateTime? readNullableDateTime(Map<String, dynamic> json, String key) {
  final Object? raw = json[key];
  if (raw is String) {
    return DateTime.tryParse(raw);
  }
  if (raw is int) {
    return DateTime.fromMillisecondsSinceEpoch(raw);
  }
  return null;
}

List<Map<String, dynamic>> readMapList(Map<String, dynamic> json, String key) {
  final Object? raw = json[key];
  if (raw is! List) {
    return const <Map<String, dynamic>>[];
  }
  final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
  for (final Object? element in raw) {
    if (element is Map) {
      out.add(asJsonMap(element));
    }
  }
  return out;
}

double clampDouble(double value, double min, double max) {
  if (value < min) {
    return min;
  }
  if (value > max) {
    return max;
  }
  return value;
}
