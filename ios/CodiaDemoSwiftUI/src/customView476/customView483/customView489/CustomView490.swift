//
//  CustomView490.swift
//
//  Created by codia-figma
//

import SwiftUI

struct CustomView490: View {
    @State public var text242Text: String = "Hello, how are you bro~"
    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(Color(red: 0.85, green: 0.85, blue: 0.85, opacity: 0.40))
                .clipShape(RoundedRectangle(cornerRadius: 48))
                .frame(width: 227, height: 46)
                HStack {
                    Spacer()
                        Text(text242Text)
                            .foregroundColor(Color(red: 0.34, green: 0.34, blue: 0.34, opacity: 1.00))
                            .font(.custom("HelveticaNeue", size: 18))
                            .lineLimit(1)
                            .frame(alignment: .center)
                            .multilineTextAlignment(.center)
                    Spacer()
                }
                .offset(y: 11.565)
        }
        .frame(width: 227, height: 46, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 48))
    }
}

struct CustomView490_Previews: PreviewProvider {
    static var previews: some View {
        CustomView490()
    }
}
