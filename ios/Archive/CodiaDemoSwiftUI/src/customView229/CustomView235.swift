//
//  CustomView235.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView235: View {
    @State public var text125Text: String = "First name"
    @State public var text126Text: String = "Username"
    @State public var text127Text: String = "Gender"
    @State public var text128Text: String = "Location"
    @State public var text129Text: String = "00/00/0000"
    @State public var text130Text: String = "Date of Birth"
    @State public var text131Text: String = "bruceli"
    @State public var text132Text: String = "Bruce"
    @State public var text133Text: String = "Li"
    @State public var text134Text: String = "Male"
    @State public var text135Text: String = "China"
    @State public var text136Text: String = "Last name"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                Rectangle()
                    .fill(Color(red: 0.85, green: 0.85, blue: 0.85, opacity: 1.00))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .frame(width: 351, height: 88)
                Rectangle()
                    .fill(Color(red: 0.85, green: 0.85, blue: 0.85, opacity: 1.00))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .frame(width: 301, height: 44)
                    .offset(y: 172)
                Rectangle()
                    .fill(Color(red: 0.85, green: 0.85, blue: 0.85, opacity: 1.00))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .frame(width: 351, height: 44)
                    .offset(y: 108)
                Rectangle()
                    .fill(Color(red: 0.85, green: 0.85, blue: 0.85, opacity: 1.00))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .frame(width: 351, height: 44)
                    .offset(y: 236)
                Rectangle()
                    .fill(Color(red: 0.85, green: 0.85, blue: 0.85, opacity: 1.00))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .frame(width: 351, height: 44)
                    .offset(y: 300)
                    HStack {
                        Spacer()
                            Text(text125Text)
                                .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37, opacity: 1.00))
                                .font(.custom("HelveticaNeue", size: 15))
                                .lineLimit(1)
                                .frame(alignment: .center)
                                .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .offset(y: 12)
                    HStack {
                        Spacer()
                            Text(text126Text)
                                .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37, opacity: 1.00))
                                .font(.custom("HelveticaNeue", size: 15))
                                .lineLimit(1)
                                .frame(alignment: .center)
                                .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .offset(y: 120)
                Text(text127Text)
                    .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37, opacity: 1.00))
                    .font(.custom("HelveticaNeue", size: 15))
                    .lineLimit(1)
                    .frame(alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .offset(x: 12, y: 248)
                Text(text128Text)
                    .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37, opacity: 1.00))
                    .font(.custom("HelveticaNeue", size: 15))
                    .lineLimit(1)
                    .frame(alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .offset(x: 12, y: 312)
                Text(text129Text)
                    .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                    .font(.custom("HelveticaNeue", size: 15))
                    .lineLimit(1)
                    .frame(alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .offset(x: 135, y: 184)
            }
            Group {
                    HStack {
                        Spacer()
                            Text(text130Text)
                                .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37, opacity: 1.00))
                                .font(.custom("HelveticaNeue", size: 15))
                                .lineLimit(1)
                                .frame(alignment: .center)
                                .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .offset(y: 184)
                Text(text131Text)
                    .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                    .font(.custom("HelveticaNeue", size: 15))
                    .lineLimit(1)
                    .frame(alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .offset(x: 135, y: 120)
                Text(text132Text)
                    .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                    .font(.custom("HelveticaNeue", size: 15))
                    .lineLimit(1)
                    .frame(alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .offset(x: 135, y: 12)
                Text(text133Text)
                    .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                    .font(.custom("HelveticaNeue", size: 15))
                    .lineLimit(1)
                    .frame(alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .offset(x: 135, y: 56)
                Text(text134Text)
                    .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                    .font(.custom("HelveticaNeue", size: 15))
                    .lineLimit(1)
                    .frame(alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .offset(x: 135, y: 248)
                Text(text135Text)
                    .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                    .font(.custom("HelveticaNeue", size: 15))
                    .lineLimit(1)
                    .frame(alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .offset(x: 135, y: 312)
                    HStack {
                        Spacer()
                            Text(text136Text)
                                .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37, opacity: 1.00))
                                .font(.custom("HelveticaNeue", size: 15))
                                .lineLimit(1)
                                .frame(alignment: .center)
                                .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .offset(y: 56)
                Rectangle()
                    .fill(Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: 0).stroke(Color(red: 0.91, green: 0.91, blue: 0.91, opacity: 1.00), lineWidth: 1))
                    .frame(width: 351, height: 1)
                    .offset(y: 44)
            }
        }
        .frame(width: 351, height: 344, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct CustomView235_Previews: PreviewProvider {
    static var previews: some View {
        CustomView235()
    }
}
