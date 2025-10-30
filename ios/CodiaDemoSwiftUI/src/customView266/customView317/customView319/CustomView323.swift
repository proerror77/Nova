//
//  CustomView323.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView323: View {
    @State public var image215Path: String = "image215_41010"
    @State public var text181Text: String = "1"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(image215Path)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 17, height: 17, alignment: .topLeading)
                .cornerRadius(8.5)
                .offset(y: 2)
                HStack {
                    Spacer()
                        Text(text181Text)
                            .foregroundColor(Color(red: 1.00, green: 1.00, blue: 1.00, opacity: 1.00))
                            .font(.custom("HelveticaNeue-Medium", size: 12))
                            .lineLimit(1)
                            .frame(alignment: .center)
                            .multilineTextAlignment(.center)
                    Spacer()
                }
        }
        .frame(width: 17, height: 20, alignment: .topLeading)
    }
}

struct CustomView323_Previews: PreviewProvider {
    static var previews: some View {
        CustomView323()
    }
}
