class Note {
  String id;
  String startTime;
  String? endTime;
  String address;
  double lat;
  double lng;

  Note({
    required this.id,
    required this.startTime,
    this.endTime,
    required this.address,
    required this.lat,
    required this.lng,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'startTime': startTime,
    'endTime': endTime,
    'address': address,
    'lat': lat,
    'lng': lng,
  };

  factory Note.fromJson(Map<String, dynamic> json) => Note(
    id: json['id'],
    startTime: json['startTime'],
    endTime: json['endTime'],
    address: json['address'],
    lat: (json['lat'] as num).toDouble(),
    lng: (json['lng'] as num).toDouble(),
  );
}
