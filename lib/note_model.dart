class Note {
  String id;
  String startTime;
  String? endTime;
  String address;
  double lat;
  double lng;
  double? endLat;
  double? endLng;
  String? endAddress;

  Note({
    required this.id,
    required this.startTime,
    this.endTime,
    required this.address,
    required this.lat,
    required this.lng,
    this.endLat,
    this.endLng,
    this.endAddress,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'startTime': startTime,
    'endTime': endTime,
    'address': address,
    'lat': lat,
    'lng': lng,
    'endLat': endLat,
    'endLng': endLng,
    'endAddress': endAddress,
  };

  factory Note.fromJson(Map<String, dynamic> json) => Note(
    id: json['id'],
    startTime: json['startTime'],
    endTime: json['endTime'],
    address: json['address'],
    lat: (json['lat'] as num).toDouble(),
    lng: (json['lng'] as num).toDouble(),
    endLat: json['endLat'] != null ? (json['endLat'] as num).toDouble() : null,
    endLng: json['endLng'] != null ? (json['endLng'] as num).toDouble() : null,
    endAddress: json['endAddress'],
  );
}
