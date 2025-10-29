//
//  CustomView390.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView390: View {
    @State public var image252Path: String = "image252_41292"
    @State public var image253Path: String = "image253_41294"
    @State public var text208Text: String = "Add a contact"
    @State public var text209Text: String = "Save"
    @State public var image254Path: String = "image254_41298"
    @State public var text210Text: String = "First name"
    @State public var text211Text: String = "Phone"
    @State public var text212Text: String = "China"
    @State public var text213Text: String = "+86"
    @State public var text214Text: String = "Last name"
    @State public var text215Text: String = "number"
    @State public var image255Path: String = "image255_41311"
    @State public var image256Path: String = "image256_41312"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                Rectangle()
                    .fill(Color(red: 0.97, green: 0.96, blue: 0.96, opacity: 1.00))
                    .frame(width: 393, height: 852)
                Rectangle()
                    .fill(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
                    .frame(width: 393, height: 113)
                Image(image252Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 393, height: 47, alignment: .topLeading)
                Rectangle()
                    .fill(Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: 0).stroke(Color(red: 0.74, green: 0.74, blue: 0.74, opacity: 1.00), lineWidth: 1))
                    .frame(width: 393, height: 1)
                    .offset(y: 114)
                Image(image253Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 350, height: 23, alignment: .topLeading)
                    .offset(x: 22, y: 66)
                    HStack {
                        Spacer()
                            Text(text208Text)
                                .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                                .font(.custom("HelveticaNeue-Medium", size: 24))
                                .lineLimit(1)
                                .frame(alignment: .center)
                                .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .offset(y: 68)
                    HStack {
                        Spacer()
                            Text(text209Text)
                                .foregroundColor(Color(red: 0.58, green: 0.58, blue: 0.58, opacity: 1.00))
                                .font(.custom("HelveticaNeue-Medium", size: 18))
                                .lineLimit(1)
                                .frame(alignment: .center)
                                .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .offset(y: 70)
                Image(image254Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 141, height: 5, alignment: .top)
                    .offset(x: 126, y: 836)
                Rectangle()
                    .fill(Color(red: 0.85, green: 0.85, blue: 0.85, opacity: 1.00))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .frame(width: 351, height: 88)
                    .offset(x: 21, y: 134)
                Rectangle()
                    .fill(Color(red: 0.85, green: 0.85, blue: 0.85, opacity: 1.00))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .frame(width: 351, height: 88)
                    .offset(x: 21, y: 242)
            }
            Group {
                Rectangle()
                    .fill(Color(red: 0.85, green: 0.85, blue: 0.85, opacity: 1.00))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .frame(width: 351, height: 44)
                    .offset(x: 21, y: 350)
                    HStack {
                        Spacer()
                            Text(text210Text)
                                .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37, opacity: 1.00))
                                .font(.custom("HelveticaNeue", size: 15))
                                .lineLimit(1)
                                .frame(alignment: .center)
                                .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .offset(y: 146)
                    HStack {
                        Spacer()
                            Text(text211Text)
                                .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37, opacity: 1.00))
                                .font(.custom("HelveticaNeue", size: 15))
                                .lineLimit(1)
                                .frame(alignment: .center)
                                .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .offset(y: 254)
                    HStack {
                        Spacer()
                            Text(text212Text)
                                .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                                .font(.custom("HelveticaNeue", size: 15))
                                .lineLimit(1)
                                .frame(alignment: .center)
                                .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .offset(y: 254)
                    HStack {
                        Spacer()
                            Text(text213Text)
                                .foregroundColor(Color(red: 0.00, green: 0.00, blue: 0.00, opacity: 1.00))
                                .font(.custom("HelveticaNeue", size: 15))
                                .lineLimit(1)
                                .frame(alignment: .center)
                                .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .offset(y: 298)
                    HStack {
                        Spacer()
                            Text(text214Text)
                                .foregroundColor(Color(red: 0.38, green: 0.37, blue: 0.37, opacity: 1.00))
                                .font(.custom("HelveticaNeue", size: 15))
                                .lineLimit(1)
                                .frame(alignment: .center)
                                .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .offset(y: 190)
                    HStack {
                        Spacer()
                            Text(text215Text)
                                .foregroundColor(Color(red: 0.82, green: 0.13, blue: 0.25, opacity: 1.00))
                                .font(.custom("HelveticaNeue", size: 15))
                                .lineLimit(1)
                                .frame(alignment: .center)
                                .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .offset(y: 298)
                Rectangle()
                    .fill(Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: 0).stroke(Color(red: 0.91, green: 0.91, blue: 0.91, opacity: 1.00), lineWidth: 1))
                    .frame(width: 351, height: 1)
                    .offset(x: 21, y: 178)
                Rectangle()
                    .fill(Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: 0).stroke(Color(red: 0.91, green: 0.91, blue: 0.91, opacity: 1.00), lineWidth: 1))
                    .frame(width: 351, height: 1)
                    .offset(x: 21, y: 286)
                Image(image255Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 5, height: 10, alignment: .topLeading)
                    .offset(x: 93, y: 304)
            }
            Group {
                Image(image256Path)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 5, height: 10, alignment: .topLeading)
                    .offset(x: 352, y: 260)
            }
        }
        .frame(width: 393, height: 852, alignment: .topLeading)
        .background(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
        .clipped()
    }
}

struct CustomView390_Previews: PreviewProvider {
    static var previews: some View {
        CustomView390()
    }
}
