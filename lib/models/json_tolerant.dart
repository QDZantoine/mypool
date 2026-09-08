/// Lectures JSON tolerantes, partagees par tous les modèles.
///
/// Règle du projet : une préférence corrompue ne doit jamais empecher
/// l'application de s'ouvrir. Chaque lecteur retombe donc sur la valeur par
/// défaut au lieu de lever une exception, que la clé soit absente, nulle,
/// d'un type inattendu ou hors bornes.
library;

/// Convertit une valeur quelconque en carte JSON exploitable.
///
/// Un objet attendu mais recu sous forme de chaîne, de liste ou de `null`
/// devient une carte vide : les lecteurs ci-dessous rendront alors tous les
/// défauts, ce qui reconstruit un modèle valide.
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

/// Lit un réel. Accepte les entiers et les chaînes numériques (une préférence
/// écrite par une version anterieure pouvait stocker `"7.2"`).
double readDouble(Map<String, dynamic> json, String key, double fallback) {
  final Object? raw = json[key];
  if (raw is num) {
    final double value = raw.toDouble();
    // Un NaN ou un infini se propagerait dans tous les calculs de dose.
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

/// Lit un réel optionnel : une clé absente reste absente (elle ne devient pas
/// zéro, sans quoi une mesure non saisie serait interpretee comme un pH de 0).
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

/// Lit une chaîne. Une chaîne vide est traitée comme absente : un libellé vide
/// n'est jamais affichable.
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

/// Lit une valeur d'enumeration par son `name`, avec repli sur l'index entier
/// pour rester compatible avec des données écrites en numérique.
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

/// Lit une date ISO 8601 ou un horodatage en millisecondes.
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

/// Lit une liste d'objets JSON. Les elements qui ne sont pas des cartes sont
/// ignores plutôt que de faire echouer toute la liste.
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

/// Borne une valeur dans un intervalle physiquement plausible.
///
/// Sert à neutraliser les données aberrantes relues du disque : un volume de
/// -40 m3 ou un rendement de pompe de 900 % feraient produire des doses
/// absurdes par le moteur de dosage.
double clampDouble(double value, double min, double max) {
  if (value < min) {
    return min;
  }
  if (value > max) {
    return max;
  }
  return value;
}
